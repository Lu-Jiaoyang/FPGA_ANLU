// Read-only FAT32 root-directory lookup, following the lesson 7 design.
// Fixed resources PIC01.BMP..PIC12.BMP; independent of directory/cluster order.
module fat32_bmp_reader #(
    parameter integer CLK_FREQ_HZ = 100000000,
    parameter integer IO_TIMEOUT_MS = 500,
    parameter integer MAX_DIR_CLUSTERS = 128
)(
    input clk, rst, sd_init_done,
    input scan_start,
    output reg scan_done,
    output reg [11:0] resource_valid,
    input load_start,
    input [3:0] load_index,
    output ready,
    output reg load_done, load_error,
    output reg [7:0] error_code,
    output reg fatal_error,
    input [15:0] bmp_width, bmp_height,
    output reg write_req,
    input write_req_ack,
    output reg sd_sec_read,
    output reg [31:0] sd_sec_read_addr,
    input [7:0] sd_sec_read_data,
    input sd_sec_read_data_valid, sd_sec_read_end,
    output bmp_data_wr_en,
    output [23:0] bmp_data,
    output [10:0] source_width, source_height
);
    // Keep the sector producer decode out of the parser's byte/field enable paths.
    reg [7:0] sector_data;
    (* max_fanout = 16 *) reg sector_valid;
    reg sector_end;
    always @(posedge clk or posedge rst) begin
        if(rst) begin sector_data<=0; sector_valid<=0; sector_end<=0; end
        else begin
            sector_data<=sd_sec_read_data;
            sector_valid<=sd_sec_read_data_valid;
            sector_end<=sd_sec_read_end;
        end
    end
    localparam [63:0] IO_CYCLES = (64'd1 * CLK_FREQ_HZ / 1000) * IO_TIMEOUT_MS;
    localparam integer TIMER_BITS = IO_CYCLES > 1 ? $clog2(IO_CYCLES) : 1;
    localparam IDLE=0, READ=1, READ_END=2, BOOT_CHECK=3, LAYOUT=4,
               GEOMETRY=5, DIR_READ=6, DIR_END=7, FAT_READ=8, FAT_END=9,
               HEADER_READ=10, HEADER_CHECK=11, WRITE_ACK=12, WRITE_RELEASE=13,
               DATA_READ=14, DATA_END=15, SCAN_END=16,
               ADDR_SHIFT=17, ADDR_BASE=18, ADDR_READ=19, GEOMETRY_CHECK=20, FAILED=21,
               FAT_CHECK=22, BOOT_VALIDATE=23, IMAGE_GEOMETRY=24, IMAGE_SIZE=25,
               DRAIN_FETCH=26, DRAIN_BYTE=27, DRAIN_PIXEL=28, DRAIN_NEXT=29, RESIZE_WAIT=30, LOAD_SELECT=31;
    localparam K_BOOT=0, K_DIR=1, K_FAT=2, K_HEADER=3, K_DATA=4;
    // Dynamic return-state dispatch prevents automatic FSM inference; decode explicit one-hot bits.
    reg [31:0] state;
    reg [3:0] selected_index;
    reg load_allowed;
    reg [4:0] return_state;
    reg [2:0] kind;
    reg [9:0] byte_count;
    reg [TIMER_BITS-1:0] timeout_count;
    reg scanning, mounted;
    reg [7:0] pending_error;
    reg pending_fatal;
    reg [31:0] clusters [0:11];
    reg [31:0] sizes [0:11];
    reg [31:0] partition_lba, partition_size;
    reg mbr_found;
    reg [7:0] mbr_status, mbr_type;
    reg [31:0] mbr_start, mbr_size;
    reg [7:0] sig0, sig1;
    reg boot_signature_ok, boot_bpb_ok;
    reg [15:0] bytes_per_sector, reserved_sectors, root_entries, total16, fat16;
    reg [7:0] sectors_per_cluster, fat_count;
    reg [15:0] ext_flags, fs_version;
    reg [31:0] total_sectors, fat_sectors, root_cluster;
    reg [2:0] cluster_shift;
    reg [32:0] data_offset, volume_end;
    reg [31:0] fat_lba, data_lba, cluster_count, max_cluster;
    reg [31:0] current_cluster;
    reg [31:0] cluster_offset, sector_base;
    reg [7:0] sector_in_cluster;
    reg [15:0] directory_clusters;
    reg [87:0] dir_name;
    reg [11:0] dir_matches;
    (* max_fanout = 16 *) reg [11:0] dir_commit;
    reg [7:0] dir_attr;
    reg [31:0] dir_cluster, dir_size;
    reg dir_end, dir_bad;
    reg [31:0] fat_value;
    reg fat_eoc, fat_bad;
    reg [31:0] file_size, bytes_left, file_offset, pixels_written;
    reg [7:0] h0, h1;
    reg [31:0] h_size, h_offset, h_dib, h_width, h_height, h_compression, h_image_size;
    // Consume this bundle only after load_done; it stays stable until the next load.
    assign source_width=h_width[10:0];
    assign source_height=h_height[10:0];
    reg [15:0] h_planes, h_bpp;
    reg [1:0] color_byte;
    reg native_valid,scaled,resize_start,resize_valid;
    reg [23:0] native_rgb,resize_rgb;
    reg [12:0] source_row_bytes,source_stride,row_byte;
    reg [23:0] source_bytes,source_pixels,output_pixels;
    reg [8:0] drain_index;
    (* ram_style="bram" *) reg [7:0] sector_buffer[0:511];
    reg [7:0] drain_byte;
    wire resize_ready,resize_done,resize_output_valid;
    wire [23:0] resize_output_rgb;
    assign bmp_data_wr_en=scaled ? resize_output_valid : native_valid;
    assign bmp_data=scaled ? resize_output_rgb : native_rgb;
    bmp_resize_stream resizer(
        .clk(clk),.rst(rst || state[FAILED]),.start(resize_start),
        .source_width(h_width[10:0]),.source_height(h_height[10:0]),
        .target_width(bmp_width),.target_height(bmp_height),
        .in_valid(resize_valid),.in_ready(resize_ready),.in_rgb(resize_rgb),
        .out_valid(resize_output_valid),.out_rgb(resize_output_rgb),.done(resize_done));
    always @(posedge clk) begin
        if(state[READ] && kind==K_DATA && scaled && sector_valid && byte_count<512)
            sector_buffer[byte_count[8:0]]<=sector_data;
        if(state[DRAIN_FETCH]) drain_byte<=sector_buffer[drain_index];
    end
    integer i;

    wire [3:0] mbr_offset = byte_count[3:0] - 4'd14;
    wire [31:0] expected_pixels = {16'd0,bmp_width} * {16'd0,bmp_height};
    wire [31:0] expected_bytes = expected_pixels * 32'd3 + 32'd54;
    wire [27:0] next_cluster = fat_value[27:0];
    wire [8:0] fat_offset = {current_cluster[6:0],2'b00};
    assign ready = state[IDLE] && !fatal_error;

    function valid_spc;
        input [7:0] n;
        begin valid_spc = n != 0 && (n & (n-1'b1)) == 0; end
    endfunction
    function [2:0] spc_log2;
        input [7:0] n;
        begin
            case(n)
                2:spc_log2=1; 4:spc_log2=2; 8:spc_log2=3; 16:spc_log2=4;
                32:spc_log2=5; 64:spc_log2=6; 128:spc_log2=7;
                default:spc_log2=0;
            endcase
        end
    endfunction
    task read_cluster_sector;
        input [2:0] read_kind;
        input [4:0] after_read;
        begin
            // Split subtract/shift/add across clocks to meet the 100 MHz SD clock.
            cluster_offset <= current_cluster-32'd2;
            kind <= read_kind; return_state <= after_read; state <= 32'b1 << ADDR_SHIFT;
        end
    endtask
    task read_sector;
        input [31:0] lba;
        input [2:0] read_kind;
        input [4:0] after_read;
        begin
            sd_sec_read_addr <= lba;
            sd_sec_read <= 1'b1;
            byte_count <= 0;
            timeout_count <= 0;
            kind <= read_kind;
            return_state <= after_read;
            state <= 32'b1 << READ;
        end
    endtask
    task fail;
        input [7:0] code;
        input fatal;
        begin
            pending_error <= code;
            pending_fatal <= fatal;
            sd_sec_read <= 0;
            write_req <= 0;
            state <= 32'b1 << FAILED;
        end
    endtask

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            state <= 32'b1 << IDLE; return_state<=IDLE; kind<=0; byte_count<=0; timeout_count<=0;
            scanning<=0; mounted<=0; scan_done<=0; resource_valid<=0;
            pending_error<=0; pending_fatal<=0;
            load_done<=0; load_error<=0; error_code<=0; fatal_error<=0;
            write_req<=0; sd_sec_read<=0; sd_sec_read_addr<=0;
            native_valid<=0; native_rgb<=0;scaled<=0;resize_start<=0;resize_valid<=0;resize_rgb<=0;
            source_row_bytes<=0;source_stride<=0;row_byte<=0;source_bytes<=0;source_pixels<=0;
            selected_index<=0;load_allowed<=0;
            output_pixels<=0;drain_index<=0;
            partition_lba<=0; partition_size<=0; mbr_found<=0;
            mbr_status<=0; mbr_type<=0; mbr_start<=0; mbr_size<=0;
            sig0<=0; sig1<=0; boot_signature_ok<=0; boot_bpb_ok<=0;
            bytes_per_sector<=0; reserved_sectors<=0;
            root_entries<=0; total16<=0; fat16<=0; sectors_per_cluster<=0;
            fat_count<=0; ext_flags<=0; fs_version<=0; total_sectors<=0;
            fat_sectors<=0; root_cluster<=0; cluster_shift<=0; data_offset<=0;
            volume_end<=0; fat_lba<=0; data_lba<=0; cluster_count<=0; max_cluster<=0;
            current_cluster<=0; cluster_offset<=0; sector_base<=0;
            sector_in_cluster<=0; directory_clusters<=0;
            dir_name<=0; dir_matches<=0; dir_commit<=0; dir_attr<=0; dir_cluster<=0; dir_size<=0;
            dir_end<=0; dir_bad<=0; fat_value<=0; fat_eoc<=0; fat_bad<=0;
            file_size<=0; bytes_left<=0; file_offset<=0; pixels_written<=0;
            h0<=0; h1<=0; h_size<=0; h_offset<=0; h_dib<=0; h_width<=0; h_height<=0;
            h_compression<=0; h_image_size<=0; h_planes<=0; h_bpp<=0; color_byte<=0;
            for(i=0;i<12;i=i+1) begin clusters[i]<=0; sizes[i]<=0; end
        end else begin
            load_done<=0; load_error<=0; native_valid<=0;resize_start<=0;
            if(resize_output_valid) output_pixels<=output_pixels+1'b1;
            dir_commit<=0;
            // Register slot enables before driving the wide directory tables at 100 MHz.
            for(i=0;i<12;i=i+1) if(dir_commit[i]) begin
                clusters[i]<={4'b0,dir_cluster[27:0]};
                sizes[i]<=dir_size;
            end
            if (state[READ] && sector_valid && byte_count < 512) begin
                byte_count <= byte_count + 1'b1;
                if (kind == K_BOOT) begin
                    case (byte_count)
                        11:bytes_per_sector[7:0]<=sector_data;
                        12:bytes_per_sector[15:8]<=sector_data;
                        13:sectors_per_cluster<=sector_data;
                        14:reserved_sectors[7:0]<=sector_data;
                        15:reserved_sectors[15:8]<=sector_data;
                        16:fat_count<=sector_data;
                        17:root_entries[7:0]<=sector_data;
                        18:root_entries[15:8]<=sector_data;
                        19:total16[7:0]<=sector_data;
                        20:total16[15:8]<=sector_data;
                        22:fat16[7:0]<=sector_data;
                        23:fat16[15:8]<=sector_data;
                        32:total_sectors[7:0]<=sector_data;
                        33:total_sectors[15:8]<=sector_data;
                        34:total_sectors[23:16]<=sector_data;
                        35:total_sectors[31:24]<=sector_data;
                        36:fat_sectors[7:0]<=sector_data;
                        37:fat_sectors[15:8]<=sector_data;
                        38:fat_sectors[23:16]<=sector_data;
                        39:fat_sectors[31:24]<=sector_data;
                        40:ext_flags[7:0]<=sector_data;
                        41:ext_flags[15:8]<=sector_data;
                        42:fs_version[7:0]<=sector_data;
                        43:fs_version[15:8]<=sector_data;
                        44:root_cluster[7:0]<=sector_data;
                        45:root_cluster[15:8]<=sector_data;
                        46:root_cluster[23:16]<=sector_data;
                        47:root_cluster[31:24]<=sector_data;
                        510:sig0<=sector_data;
                        511:sig1<=sector_data;
                        default:;
                    endcase
                    if (partition_lba == 0 && byte_count >= 446 && byte_count < 510) begin
                        case (mbr_offset)
                            0:mbr_status<=sector_data;
                            4:mbr_type<=sector_data;
                            8:mbr_start[7:0]<=sector_data;
                            9:mbr_start[15:8]<=sector_data;
                            10:mbr_start[23:16]<=sector_data;
                            11:mbr_start[31:24]<=sector_data;
                            12:mbr_size[7:0]<=sector_data;
                            13:mbr_size[15:8]<=sector_data;
                            14:mbr_size[23:16]<=sector_data;
                            15:if (!mbr_found && (mbr_status==0 || mbr_status==8'h80) &&
                                  (mbr_type==8'h0b || mbr_type==8'h0c) && mbr_start!=0) begin
                                mbr_found<=1;
                                // Freeze the selected entry separately from subsequent MBR entries.
                                partition_size<={sector_data,mbr_size[23:0]};
                                // clusters[0] is scratch until directory scanning begins.
                                clusters[0]<=mbr_start;
                            end
                            default:;
                        endcase
                    end
                end
                if (kind == K_DIR && !dir_end) begin
                    if (byte_count[4:0] <= 10) dir_name <= {dir_name[79:0],sector_data};
                    case (byte_count[4:0])
                        0:if(sector_data==0) dir_end<=1;
                        11:begin
                            dir_attr<=sector_data;
                            // Decode before the remaining directory fields arrive, shortening the slot write path.
                            dir_matches<={dir_name=="PIC12   BMP",dir_name=="PIC11   BMP",
                                          dir_name=="PIC10   BMP",dir_name=="PIC09   BMP",
                                          dir_name=="PIC08   BMP",dir_name=="PIC07   BMP",
                                          dir_name=="PIC06   BMP",dir_name=="PIC05   BMP",
                                          dir_name=="PIC04   BMP",dir_name=="PIC03   BMP",
                                          dir_name=="PIC02   BMP",dir_name=="PIC01   BMP"};
                        end
                        20:dir_cluster[23:16]<=sector_data;
                        21:dir_cluster[31:24]<=sector_data;
                        26:dir_cluster[7:0]<=sector_data;
                        27:dir_cluster[15:8]<=sector_data;
                        28:dir_size[7:0]<=sector_data;
                        29:dir_size[15:8]<=sector_data;
                        30:dir_size[23:16]<=sector_data;
                        31:begin
                          dir_size[31:24]<=sector_data;
                          if((dir_attr & 8'hd8)==0) begin
                            // Use the registered one-hot match directly; avoid encoding and re-decoding twelve slots.
                            for(i=0;i<12;i=i+1) if(dir_matches[i]) begin
                                if(resource_valid[i]) dir_bad<=1;
                                else begin
                                    resource_valid[i]<=1;
                                    dir_commit[i]<=1;
                                end
                            end
                          end
                        end
                        default:;
                    endcase
                end
                if (kind == K_FAT) begin
                    if (byte_count == {1'b0,fat_offset}) fat_value[7:0]<=sector_data;
                    if (byte_count == {1'b0,fat_offset}+10'd1) fat_value[15:8]<=sector_data;
                    if (byte_count == {1'b0,fat_offset}+10'd2) fat_value[23:16]<=sector_data;
                    if (byte_count == {1'b0,fat_offset}+10'd3) fat_value[31:24]<=sector_data;
                end
                if (kind == K_HEADER) begin
                    case(byte_count)
                        0:h0<=sector_data; 1:h1<=sector_data;
                        2:h_size[7:0]<=sector_data; 3:h_size[15:8]<=sector_data;
                        4:h_size[23:16]<=sector_data; 5:h_size[31:24]<=sector_data;
                        10:h_offset[7:0]<=sector_data; 11:h_offset[15:8]<=sector_data;
                        12:h_offset[23:16]<=sector_data; 13:h_offset[31:24]<=sector_data;
                        14:h_dib[7:0]<=sector_data; 15:h_dib[15:8]<=sector_data;
                        16:h_dib[23:16]<=sector_data; 17:h_dib[31:24]<=sector_data;
                        18:h_width[7:0]<=sector_data; 19:h_width[15:8]<=sector_data;
                        20:h_width[23:16]<=sector_data; 21:h_width[31:24]<=sector_data;
                        22:h_height[7:0]<=sector_data; 23:h_height[15:8]<=sector_data;
                        24:h_height[23:16]<=sector_data; 25:h_height[31:24]<=sector_data;
                        26:h_planes[7:0]<=sector_data; 27:h_planes[15:8]<=sector_data;
                        28:h_bpp[7:0]<=sector_data; 29:h_bpp[15:8]<=sector_data;
                        30:h_compression[7:0]<=sector_data; 31:h_compression[15:8]<=sector_data;
                        32:h_compression[23:16]<=sector_data; 33:h_compression[31:24]<=sector_data;
                        34:h_image_size[7:0]<=sector_data; 35:h_image_size[15:8]<=sector_data;
                        36:h_image_size[23:16]<=sector_data; 37:h_image_size[31:24]<=sector_data;
                        default:;
                    endcase
                end
                if (kind == K_DATA && !scaled && bytes_left != 0) begin
                    bytes_left<=bytes_left-1'b1;
                    file_offset<=file_offset+1'b1;
                    if (file_offset >= 54) begin
                        case(color_byte)
                            0:begin native_rgb[7:0]<=sector_data; color_byte<=1; end
                            1:begin native_rgb[15:8]<=sector_data; color_byte<=2; end
                            2:begin
                                native_rgb[23:16]<=sector_data; color_byte<=0;
                                native_valid<=1; pixels_written<=pixels_written+1'b1;
                            end
                            default:color_byte<=0;
                        endcase
                    end
                end
            end

            // State is one-hot; do not build a priority chain through unrelated error paths.
            (* parallel_case *) case(1'b1)
                state[FAILED]:begin
                    // Apply cleanup after the failing condition is registered, keeping validation paths short.
                    error_code<=pending_error; fatal_error<=pending_fatal; state <= 32'b1 << IDLE;
                    if(scanning) begin scan_done<=1; mounted<=0; resource_valid<=0; end
                    else load_error<=1;
                end
                state[IDLE]:if(!fatal_error && sd_init_done) begin
                    if(scan_start) begin
                        scanning<=1; mounted<=0; scan_done<=0; resource_valid<=0;
                        error_code<=0; partition_lba<=0; partition_size<=0; mbr_found<=0;
                        dir_end<=0; dir_bad<=0;
                        read_sector(0,K_BOOT,BOOT_VALIDATE);
                    end else if(load_start) begin
                        scanning<=0; error_code<=0;
                        selected_index<=load_index;
                        load_allowed<=mounted && load_index<12 && resource_valid[load_index];
                        state<=32'b1<<LOAD_SELECT;
                    end
                end
                state[LOAD_SELECT]:begin
                    // Separate resource validation from the wide cluster/size register enables.
                    current_cluster<=clusters[selected_index];file_size<=sizes[selected_index];
                    file_offset<=0;pixels_written<=0;output_pixels<=0;resize_valid<=0;row_byte<=0;
                    color_byte<=0;sector_in_cluster<=0;
                    if(!load_allowed) fail(8'h15,1'b0);
                    else state<=32'b1<<HEADER_READ;
                end
                state[READ]:begin
                    timeout_count<=timeout_count+1'b1;
                    // Release on the raw end pulse before the controller accepts another request.
                    if(sd_sec_read_end) sd_sec_read<=0;
                    if(sector_valid && byte_count==512) fail(8'h11,1'b1);
                    else if(sector_end) state <= 32'b1 << READ_END;
                    else if(timeout_count==IO_CYCLES-1) fail(8'h10,1'b1);
                end
                state[READ_END]:if(byte_count!=512) fail(8'h11,1'b1); else state <= 32'b1 << return_state;
                state[BOOT_VALIDATE]:begin
                    boot_signature_ok<=sig0==8'h55 && sig1==8'haa;
                    boot_bpb_ok<=bytes_per_sector==512 && valid_spc(sectors_per_cluster) &&
                            reserved_sectors!=0 && (fat_count==1 || fat_count==2) &&
                            root_entries==0 && total16==0 && fat16==0 && fat_sectors!=0 &&
                            total_sectors!=0 && fs_version==0 && root_cluster[31:28]==0 &&
                            (!ext_flags[7] || {4'd0,ext_flags[3:0]}<fat_count);
                    state <= 32'b1 << BOOT_CHECK;
                end
                state[BOOT_CHECK]:begin
                    if(!boot_signature_ok) fail(8'h12,1'b0);
                    else if(boot_bpb_ok) begin
                        cluster_shift<=spc_log2(sectors_per_cluster);
                        data_offset<={17'd0,reserved_sectors}+
                            (fat_count==2 ? {fat_sectors,1'b0} : {1'b0,fat_sectors});
                        volume_end<={1'b0,partition_lba}+{1'b0,total_sectors};
                        state <= 32'b1 << LAYOUT;
                    end else if(partition_lba==0 && mbr_found && partition_size!=0) begin
                        partition_lba<=clusters[0];
                        read_sector(clusters[0],K_BOOT,BOOT_VALIDATE);
                    end else fail(8'h12,1'b0);
                end
                state[LAYOUT]:begin
                    if(data_offset>={1'b0,total_sectors} || volume_end>33'h100000000 ||
                       (partition_lba!=0 && total_sectors>partition_size)) fail(8'h13,1'b0);
                    else begin
                        fat_lba<=partition_lba+{16'd0,reserved_sectors}+
                            ((ext_flags[7] && ext_flags[3:0]==1) ? fat_sectors : 32'd0);
                        data_lba<=partition_lba+data_offset[31:0];
                        cluster_count<=(total_sectors-data_offset[31:0])>>cluster_shift;
                        state <= 32'b1 << GEOMETRY;
                    end
                end
                state[GEOMETRY]:begin
                    max_cluster<=cluster_count+32'd1; state <= 32'b1 << GEOMETRY_CHECK;
                end
                state[GEOMETRY_CHECK]:begin
                    if(cluster_count<65525 || cluster_count>32'h0fffffee ||
                       {7'd0,max_cluster}>={fat_sectors,7'b0} ||
                       root_cluster<2 || root_cluster>max_cluster) fail(8'h13,1'b0);
                    else begin
                        current_cluster<=root_cluster;
                        sector_in_cluster<=0; directory_clusters<=1; state <= 32'b1 << DIR_READ;
                    end
                end
                state[ADDR_SHIFT]:begin cluster_offset<=cluster_offset<<cluster_shift; state <= 32'b1 << ADDR_BASE; end
                state[ADDR_BASE]:begin sector_base<=data_lba+cluster_offset; state <= 32'b1 << ADDR_READ; end
                state[ADDR_READ]:read_sector(sector_base+sector_in_cluster,kind,return_state);
                state[DIR_READ]:read_cluster_sector(K_DIR,DIR_END);
                state[DIR_END]:begin
                    if(dir_bad) fail(8'h14,1'b0);
                    else if(dir_end) state <= 32'b1 << SCAN_END;
                    else if(sector_in_cluster+8'd1<sectors_per_cluster) begin
                        sector_in_cluster<=sector_in_cluster+1'b1; state <= 32'b1 << DIR_READ;
                    end else state <= 32'b1 << FAT_READ;
                end
                state[FAT_READ]:read_sector(fat_lba+(current_cluster>>7),K_FAT,FAT_CHECK);
                state[FAT_CHECK]:begin
                    fat_eoc<=next_cluster>=28'hffffff8;
                    fat_bad<=next_cluster<2 || {4'b0,next_cluster}>max_cluster ||
                             next_cluster>=28'hffffff0 || {4'b0,next_cluster}==current_cluster;
                    state <= 32'b1 << FAT_END;
                end
                state[FAT_END]:begin
                    if(fat_eoc) begin
                        if(scanning) state <= 32'b1 << SCAN_END;
                        else if(bytes_left!=0) fail(8'h22,1'b0);
                        else if(pixels_written!=(scaled ? {8'd0,source_pixels} : expected_pixels) || color_byte!=0)
                            fail(8'h31,1'b0);
                        else if(scaled) begin timeout_count<=0;state<=32'b1<<RESIZE_WAIT;end
                        else begin load_done<=1; state <= 32'b1 << IDLE; end
                    end else if(fat_bad) fail(8'h21,1'b0);
                    else if(scanning && directory_clusters>=MAX_DIR_CLUSTERS) fail(8'h23,1'b0);
                    else if(!scanning && bytes_left==0) fail(8'h21,1'b0);
                    else begin
                        current_cluster<={4'b0,next_cluster}; sector_in_cluster<=0;
                        if(scanning) begin directory_clusters<=directory_clusters+1'b1; state <= 32'b1 << DIR_READ; end
                        else state <= 32'b1 << DATA_READ;
                    end
                end
                state[SCAN_END]:begin
                    scan_done<=1; mounted<=1; state <= 32'b1 << IDLE;
                    if(resource_valid==0) error_code<=8'h15;
                end
                state[HEADER_READ]:begin
                    // Reuse the latched size instead of feeding the byte counter from the directory mux.
                    bytes_left<=file_size;
                    if(current_cluster<2 || current_cluster>max_cluster) fail(8'h21,1'b0);
                    else read_cluster_sector(K_HEADER,HEADER_CHECK);
                end
                state[HEADER_CHECK]:begin
                    // Bounds precede geometry arithmetic; compressed/top-down/other DIBs remain explicit errors.
                    if(h0!="B" || h1!="M" || h_dib!=40 || h_offset!=54 || h_planes!=1 ||
                       h_bpp!=24 || h_compression!=0 || h_width==0 || h_width>1920 ||
                       h_height==0 || h_height>1080 || bmp_width==0 || bmp_width>640 ||
                       bmp_height==0 || bmp_height>480 || bmp_width[1:0]!=0) fail(8'h30,1'b0);
                    else begin
                        source_row_bytes<={2'b0,h_width[10:0]}*13'd3;
                        source_stride<=(({2'b0,h_width[10:0]}*13'd3+13'd3)>>2)<<2;
                        scaled<=h_width!={16'd0,bmp_width} || h_height!={16'd0,bmp_height};
                        state<=32'b1<<IMAGE_GEOMETRY;
                    end
                end
                state[IMAGE_GEOMETRY]:begin
                    source_bytes<=source_stride*h_height[10:0]+24'd54;
                    source_pixels<=h_width[10:0]*h_height[10:0];state<=32'b1<<IMAGE_SIZE;
                end
                state[IMAGE_SIZE]:if(file_size!={8'd0,source_bytes} || h_size!=file_size ||
                    (h_image_size!=0 && h_image_size!={8'd0,source_bytes}-32'd54)) fail(8'h30,1'b0);
                else begin
                    write_req<=1;timeout_count<=0;resize_start<=scaled;state<=32'b1<<WRITE_ACK;
                end
                state[WRITE_ACK]:begin
                    timeout_count<=timeout_count+1'b1;
                    if(write_req_ack) begin write_req<=0; timeout_count<=0; state <= 32'b1 << WRITE_RELEASE; end
                    else if(timeout_count==IO_CYCLES-1) fail(8'h32,1'b1);
                end
                state[WRITE_RELEASE]:begin
                    timeout_count<=timeout_count+1'b1;
                    if(!write_req_ack) state <= 32'b1 << DATA_READ;
                    else if(timeout_count==IO_CYCLES-1) fail(8'h32,1'b1);
                end
                state[DATA_READ]:begin
                    drain_index<=0;
                    read_cluster_sector(K_DATA,scaled ? DRAIN_FETCH : DATA_END);
                end
                state[DRAIN_FETCH]:state<=32'b1<<DRAIN_BYTE;
                state[DRAIN_BYTE]:begin
                    state<=32'b1<<DRAIN_NEXT;
                    if(bytes_left!=0) begin
                        bytes_left<=bytes_left-1'b1;file_offset<=file_offset+1'b1;
                        if(file_offset>=54) begin
                            row_byte<=row_byte==source_stride-1'b1 ? 13'd0 : row_byte+1'b1;
                            if(row_byte<source_row_bytes) case(color_byte)
                                0:begin resize_rgb[7:0]<=drain_byte;color_byte<=1;end
                                1:begin resize_rgb[15:8]<=drain_byte;color_byte<=2;end
                                2:begin
                                    resize_rgb[23:16]<=drain_byte;color_byte<=0;
                                    pixels_written<=pixels_written+1'b1;resize_valid<=1;
                                    state<=32'b1<<DRAIN_PIXEL;
                                end
                                default:color_byte<=0;
                            endcase
                        end
                    end
                end
                state[DRAIN_PIXEL]:if(resize_ready) begin resize_valid<=0;state<=32'b1<<DRAIN_NEXT;end
                state[DRAIN_NEXT]:if(drain_index==511 || bytes_left==0) state<=32'b1<<DATA_END;
                else begin drain_index<=drain_index+1'b1;state<=32'b1<<DRAIN_FETCH;end
                state[RESIZE_WAIT]:begin
                    timeout_count<=timeout_count+1'b1;
                    if(resize_done) begin
                        if(output_pixels!=expected_pixels) fail(8'h31,1'b0);
                        else begin load_done<=1;state<=32'b1<<IDLE;end
                    end else if(timeout_count==IO_CYCLES-1) fail(8'h31,1'b0);
                end
                state[DATA_END]:begin
                    if(bytes_left==0) state <= 32'b1 << FAT_READ;
                    else if(sector_in_cluster+8'd1<sectors_per_cluster) begin
                        sector_in_cluster<=sector_in_cluster+1'b1; state <= 32'b1 << DATA_READ;
                    end else state <= 32'b1 << FAT_READ;
                end
                default:fail(8'h13,1'b1);
            endcase
        end
    end
endmodule
