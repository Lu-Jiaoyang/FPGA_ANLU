// A sparse FAT32 disk behind the original sector interface. No RTL filesystem model.
module sd_card_top(
    input clk, rst,
    output SD_nCS, SD_DCLK, SD_MOSI,
    input SD_MISO,
    output sd_init_done,
    input sd_sec_read,
    input [31:0] sd_sec_read_addr,
    output reg [7:0] sd_sec_read_data,
    output reg sd_sec_read_data_valid, sd_sec_read_end,
    input sd_sec_write,
    input [31:0] sd_sec_write_addr,
    input [7:0] sd_sec_write_data,
    output sd_sec_write_data_req, sd_sec_write_end
);
    integer width=640, height=480;
    localparam FILE_GAP=20000, FAT_SECTORS=2400, CLUSTERS=300000;
    integer partition=2048, spc=2, active_fat=0;
    integer missing_mask=0;
    integer missing=0, bad_header=0, early_eof=0, chain_loop=0;
    integer bad_bpb=0, duplicate=0, dir_loop=0, truncated=0;
    integer short_sector=0, extra_sector=0, stall=0, init_delay=0;
    integer reads=0, init_count=0, pos=0, phase=0, gap=0;
    reg continuous_bytes=0;
    reg [31:0] lba;
    assign sd_init_done=!rst && init_count>=init_delay;
    assign SD_nCS=1; assign SD_DCLK=0; assign SD_MOSI=1;
    assign sd_sec_write_data_req=0; assign sd_sec_write_end=0;

    function automatic integer byte_of(input integer v, input integer b);
        byte_of=(v>>(b*8))&255;
    endfunction
    function automatic [7:0] pixel_byte(input integer id, input integer offset);
        integer p, c;
        begin
            p=offset/3; c=offset%3;
            case(c)
                0:pixel_byte=(p+id*17)&255;
                1:pixel_byte=((p>>8)+id*29)&255;
                2:pixel_byte=((p>>16)+id*41)&255;
            endcase
        end
    endfunction
    function automatic [7:0] file_byte(input integer id, input integer off);
        integer sz;
        begin
            sz=54+((width*3+3)/4)*4*height;
            file_byte=0;
            case(off)
                0:file_byte=(bad_header==id) ? "X" : "B";
                1:file_byte="M";
                10:file_byte=54; 14:file_byte=40;
                26:file_byte=1; 28:file_byte=24;
                default:begin
                    if(off>=2 && off<6) file_byte=byte_of(sz,off-2);
                    if(off>=18 && off<22) file_byte=byte_of(width,off-18);
                    if(off>=22 && off<26) file_byte=byte_of(height,off-22);
                    if(off>=34 && off<38) file_byte=byte_of(((width*3+3)/4)*4*height,off-34);
                    if(off>=54 && off<sz) begin
                        if((off-54)%(((width*3+3)/4)*4)<width*3)
                            file_byte=pixel_byte(id,((off-54)/(((width*3+3)/4)*4))*width*3+(off-54)%(((width*3+3)/4)*4));
                        else file_byte=8'ha5;
                    end
                end
            endcase
        end
    endfunction
    function automatic [7:0] directory_byte(input integer section, input integer off);
        integer entry, k, id, cl, sz;
        reg [87:0] name;
        begin
            entry=off/32; k=off%32; id=0;
            directory_byte=(k==0) ? 8'he5 : 0;
            // All desired resources are outside the first directory sector.
            if(section==1 && entry==0) id=4;
            if(section==1 && entry>=1 && entry<=8) id=13-entry;
            if(section==2 && entry==0) id=2;
            if(section==2 && entry==1) id=1;
            if(section==3 && entry==0) id=3;
            if(section==3 && entry==1 && duplicate!=0) id=1;
            if(section==3 && entry==2 && dir_loop==0) directory_byte=0;
            if(id!=0 && missing!=id && (missing_mask & (1 << (id-1)))==0) begin
                case(id)
                    1:name="PIC01   BMP"; 2:name="PIC02   BMP";
                    3:name="PIC03   BMP"; 4:name="PIC04   BMP";
                    5:name="PIC05   BMP"; 6:name="PIC06   BMP";
                    7:name="PIC07   BMP"; 8:name="PIC08   BMP";
                    9:name="PIC09   BMP"; 10:name="PIC10   BMP";
                    11:name="PIC11   BMP"; 12:name="PIC12   BMP";
                endcase
                cl=400+(id-1)*FILE_GAP; sz=54+((width*3+3)/4)*4*height;
                if(truncated==id) sz=sz-3;
                directory_byte=0;
                if(k<=10) directory_byte=name[87-k*8 -:8];
                if(k==11) directory_byte=id==2 ? 8'h01 : 8'h20;
                if(k==20 || k==21) directory_byte=byte_of(cl,k-18);
                if(k==26 || k==27) directory_byte=byte_of(cl,k-26);
                if(k>=28) directory_byte=byte_of(sz,k-28);
            end
            // Long-name, deleted and near-name entries must not claim PIC01.
            if(section==0 && entry==0) directory_byte=k==0 ? 8'he5 : 0;
            if(section==0 && entry==1) begin
                name="PIC01   BMP";
                if(k<=10) directory_byte=name[87-k*8 -:8];
                if(k==11) directory_byte=8'h0f;
            end
            if(section==0 && entry==2) begin
                name="PIC01X  BMP";
                if(k<=10) directory_byte=name[87-k*8 -:8];
                if(k==11) directory_byte=8'h20;
            end
        end
    endfunction
    function automatic [7:0] disk_byte(input integer addr, input integer off);
        integer fat0,data0,rel,cl,sec,id,base,block,nblocks,nextc,sz,section;
        begin
            fat0=partition+32; data0=partition+32+2*FAT_SECTORS;
            disk_byte=0;
            if(addr==0 && partition!=0) begin
                // Deliberately use the third primary partition entry.
                if(off==482) disk_byte=8'h0c;
                if(off>=486 && off<490) disk_byte=byte_of(partition,off-486);
                if(off>=490 && off<494) disk_byte=byte_of(32+(2*FAT_SECTORS)+CLUSTERS*spc,off-490);
                if(off==510) disk_byte=8'h55;
                if(off==511) disk_byte=8'haa;
            end else if(addr==partition) begin
                case(off)
                    0:disk_byte=8'heb; 11:disk_byte=0; 12:disk_byte=bad_bpb!=0 ? 4 : 2;
                    13:disk_byte=spc; 14:disk_byte=32; 16:disk_byte=2;
                    40:disk_byte=active_fat!=0 ? 8'h81 : 0;
                    44:disk_byte=5;
                    510:disk_byte=8'h55; 511:disk_byte=8'haa;
                    default:begin
                        if(off>=32 && off<36) disk_byte=byte_of(32+(2*FAT_SECTORS)+CLUSTERS*spc,off-32);
                        if(off>=36 && off<40) disk_byte=byte_of(FAT_SECTORS,off-36);
                    end
                endcase
            end else if(addr>=fat0 && addr<fat0+(2*FAT_SECTORS)) begin
                cl=((addr-fat0)%FAT_SECTORS)*128+off/4; nextc=0;
                if(cl==5) nextc=11;
                if(cl==11) nextc=dir_loop!=0 ? 5 : 32'h0fffffff;
                for(id=1;id<=12;id=id+1) begin
                    base=400+(id-1)*FILE_GAP; sz=54+((width*3+3)/4)*4*height;
                    nblocks=(sz+spc*512-1)/(spc*512);
                    if(cl>=base && (cl-base)%3==0 && (cl-base)/3<nblocks) begin
                        block=(cl-base)/3;
                        nextc=block==nblocks-1 ? 32'h0fffffff : cl+3;
                        if(early_eof==id && block==0) nextc=32'h0fffffff;
                        if(chain_loop==id) nextc=block==0 ? cl+3 : base;
                    end
                end
                if(active_fat!=0 && addr<fat0+FAT_SECTORS) nextc=0;
                disk_byte=byte_of(nextc,off%4);
            end else if(addr>=data0) begin
                rel=addr-data0; cl=rel/spc+2; sec=rel%spc;
                if(cl==5 || cl==11) begin
                    section=(cl==5 ? 0 : spc)+sec;
                    disk_byte=directory_byte(section,off);
                end else begin
                    for(id=1;id<=12;id=id+1) begin
                        base=400+(id-1)*FILE_GAP;
                        if(cl>=base && cl<base+FILE_GAP && (cl-base)%3==0) begin
                            block=(cl-base)/3;
                            disk_byte=file_byte(id,(block*spc+sec)*512+off);
                        end
                    end
                end
            end
        end
    endfunction

    always @(posedge clk) begin
        sd_sec_read_data_valid<=0; sd_sec_read_end<=0;
        if(rst) begin phase<=0; pos<=0; gap<=0; init_count<=0; reads<=0; end
        else begin
            if(init_count<init_delay) init_count<=init_count+1;
            if(sd_sec_write) $fatal(1,"FAT reader attempted a card write");
            case(phase)
                0:if(sd_sec_read && sd_init_done) begin
                    lba<=sd_sec_read_addr; pos<=0; phase<=1; gap<=0; reads<=reads+1;
                end
                1:if(!stall) begin
                    if(gap==0) begin
                        sd_sec_read_data<=disk_byte(lba,pos); sd_sec_read_data_valid<=1;
                        if(pos==(short_sector ? 510 : 511)) phase<=2;
                        else pos<=pos+1;
                        gap<=continuous_bytes ? 0 : 1;
                    end else gap<=0;
                end
                2:begin
                    sd_sec_read_end<=1; phase<=3;
                    if(extra_sector) begin sd_sec_read_data_valid<=1; sd_sec_read_data<=0; end
                end
                // The real controller returns to accepting requests without waiting for request low.
                3:phase<=0;
            endcase
        end
    end
endmodule
