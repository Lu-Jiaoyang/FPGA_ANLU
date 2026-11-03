// One settings snapshot drives both the image and the OSD for the whole frame.
module picture_osd(
    input clk,rst,hs,vs,de,
    input [23:0] rgb,
    input [15:0] settings_bundle,
    input settings_toggle,
    output reg settings_ack,
    output [3:0] bright,contrast,
    output reg hs_out,vs_out,de_out,
    output reg [23:0] rgb_out,
    input [10:0] source_width,source_height,
    output [2:0] volume
);
    (* async_reg="true" *) reg [1:0] request_sync;
    reg [15:0] active;
    reg de_d,vs_d;
    reg [9:0] x;
    reg [8:0] y;
    wire [9:0] px=de_d ? x : 10'd0;
    assign volume=active[15:13];
    assign bright=active[7:4];
    assign contrast=active[3:0];
    function [15:0] decimal_size;
        input [10:0] value;
        integer i,j;
        reg [15:0] bcd;
        begin
            bcd=0;
            for(i=10;i>=0;i=i-1) begin
                for(j=0;j<4;j=j+1)
                    if(bcd[j*4+:4]>=5) bcd[j*4+:4]=bcd[j*4+:4]+4'd3;
                bcd={bcd[14:0],value[i]};
            end
            decimal_size=bcd;
        end
    endfunction
    reg [15:0] width_digits,height_digits;
    // Dimensions change with the displayed bank in vertical blanking, before these two stages.
    always @(posedge clk or posedge rst) begin
        if(rst) begin width_digits<=0;height_digits<=0;end
        else begin width_digits<=decimal_size(source_width);height_digits<=decimal_size(source_height);end
    end
    function [34:0] glyph;
        input [7:0] c;
        begin
            case(c)
                "0":glyph=35'b01110_10001_10011_10101_11001_10001_01110;
                "1":glyph=35'b00100_01100_00100_00100_00100_00100_01110;
                "2":glyph=35'b01110_10001_00001_00010_00100_01000_11111;
                "3":glyph=35'b11110_00001_00001_01110_00001_00001_11110;
                "4":glyph=35'b00010_00110_01010_10010_11111_00010_00010;
                "5":glyph=35'b11111_10000_10000_11110_00001_00001_11110;
                "6":glyph=35'b01110_10000_10000_11110_10001_10001_01110;
                "7":glyph=35'b11111_00001_00010_00100_01000_01000_01000;
                "8":glyph=35'b01110_10001_10001_01110_10001_10001_01110;
                "9":glyph=35'b01110_10001_10001_01111_00001_00001_01110;
                "B":glyph=35'b11110_10001_10001_11110_10001_10001_11110;
                "R":glyph=35'b11110_10001_10001_11110_10100_10010_10001;
                "T":glyph=35'b11111_00100_00100_00100_00100_00100_00100;
                "C":glyph=35'b01111_10000_10000_10000_10000_10000_01111;
                "O":glyph=35'b01110_10001_10001_10001_10001_10001_01110;
                "V":glyph=35'b10001_10001_10001_10001_10001_01010_00100;
                "L":glyph=35'b10000_10000_10000_10000_10000_10000_11111;
                "N":glyph=35'b10001_11001_10101_10011_10001_10001_10001;
                "P":glyph=35'b11110_10001_10001_11110_10000_10000_10000;
                "I":glyph=35'b01110_00100_00100_00100_00100_00100_01110;
                "x":glyph=35'b00000_00000_10001_01010_00100_01010_10001;
                "s":glyph=35'b00000_01111_10000_01110_00001_11110_00000;
                "-":glyph=35'b00000_00000_00000_11111_00000_00000_00000;
                "%":glyph=35'b11001_11010_00100_01000_10110_00110_00000;
                default:glyph=0;
            endcase
        end
    endfunction
    // SimSun 16px bitmap labels; nearest-neighbour 2x scaling in the central menu.
    function [63:0] label_scan;
        input [2:0] row;
        input [3:0] line_y;
        begin
            case({row,line_y})
                7'd0:label_scan=64'h0040201002000000;
                7'd1:label_scan=64'h0440108801000000;
                7'd2:label_scan=64'h042010887FFC0000;
                7'd3:label_scan=64'h08207CBE02000000;
                7'd4:label_scan=64'h1010008044440000;
                7'd5:label_scan=64'h20082A942F880000;
                7'd6:label_scan=64'h4004128811100000;
                7'd7:label_scan=64'h9FE2FEBE22480000;
                7'd8:label_scan=64'h042012884FE40000;
                7'd9:label_scan=64'h0420108800200000;
                7'd10:label_scan=64'h04207C9C01000000;
                7'd11:label_scan=64'h08201108FFFE0000;
                7'd12:label_scan=64'h0820110801000000;
                7'd13:label_scan=64'h1020220801000000;
                7'd14:label_scan=64'h2140240801000000;
                7'd15:label_scan=64'h4080400801000000;
                7'd16:label_scan=64'h0200010000000000;
                7'd17:label_scan=64'h0100008000000000;
                7'd18:label_scan=64'h7FFC3FFE00000000;
                7'd19:label_scan=64'h0000222000000000;
                7'd20:label_scan=64'h1FF0222000000000;
                7'd21:label_scan=64'h10103FFC00000000;
                7'd22:label_scan=64'h1FF0222000000000;
                7'd23:label_scan=64'h0000222000000000;
                7'd24:label_scan=64'h7FFE23E000000000;
                7'd25:label_scan=64'h4002200000000000;
                7'd26:label_scan=64'h8FE42FF000000000;
                7'd27:label_scan=64'h0820241000000000;
                7'd28:label_scan=64'h0820422000000000;
                7'd29:label_scan=64'h102241C000000000;
                7'd30:label_scan=64'h2022863000000000;
                7'd31:label_scan=64'hC01E380E00000000;
                7'd32:label_scan=64'h0010008001000000;
                7'd33:label_scan=64'h0010208000800000;
                7'd34:label_scan=64'h001020803FFE0000;
                7'd35:label_scan=64'h7E10208422200000;
                7'd36:label_scan=64'h02FE208822200000;
                7'd37:label_scan=64'h021020903FFC0000;
                7'd38:label_scan=64'h24103EA022200000;
                7'd39:label_scan=64'h149020C022200000;
                7'd40:label_scan=64'h0850208023E00000;
                7'd41:label_scan=64'h0850208020000000;
                7'd42:label_scan=64'h141020802FF00000;
                7'd43:label_scan=64'h1210208224100000;
                7'd44:label_scan=64'h2210268242200000;
                7'd45:label_scan=64'h4010388241C00000;
                7'd46:label_scan=64'h0050207E86300000;
                7'd47:label_scan=64'h00200000380E0000;
                7'd48:label_scan=64'h204020783FF82200;
                7'd49:label_scan=64'h204027C02108227C;
                7'd50:label_scan=64'h20A0224821087F44;
                7'd51:label_scan=64'hFCA021502FE82244;
                7'd52:label_scan=64'h4110FBFC21082244;
                7'd53:label_scan=64'h5208215021083E7C;
                7'd54:label_scan=64'h940622483FF82244;
                7'd55:label_scan=64'hFD102C0620082244;
                7'd56:label_scan=64'h112033F827C83E44;
                7'd57:label_scan=64'h1140E2482448227C;
                7'd58:label_scan=64'h1D80224824482244;
                7'd59:label_scan=64'hF10023F827C8FF44;
                7'd60:label_scan=64'h5104224840080484;
                7'd61:label_scan=64'h1104224840282284;
                7'd62:label_scan=64'h10FCA3F880104114;
                7'd63:label_scan=64'h1000420800008208;
                7'd64:label_scan=64'h02001FF000000000;
                7'd65:label_scan=64'h0100101000000000;
                7'd66:label_scan=64'h3FF81FF000000000;
                7'd67:label_scan=64'h0000101000000000;
                7'd68:label_scan=64'h0820FFFE00000000;
                7'd69:label_scan=64'h0440000000000000;
                7'd70:label_scan=64'hFFFE1FF000000000;
                7'd71:label_scan=64'h0000111000000000;
                7'd72:label_scan=64'h1FF01FF000000000;
                7'd73:label_scan=64'h1010111000000000;
                7'd74:label_scan=64'h10101FF000000000;
                7'd75:label_scan=64'h1FF0010000000000;
                7'd76:label_scan=64'h10101FF000000000;
                7'd77:label_scan=64'h1010010000000000;
                7'd78:label_scan=64'h1FF07FFC00000000;
                7'd79:label_scan=64'h1010000000000000;
                default:label_scan=0;
            endcase
        end
    endfunction
    function [7:0] value_char;
        input [2:0] row;
        input [3:0] index;
        input [3:0] b,c;
        input [1:0] period;
        input [2:0] vol;
        input [15:0] w,h;
        reg [11:0] percent;
        reg [15:0] size;
        reg [3:0] digit,level;
        reg [7:0] seconds;
        begin
            level=row==1 ? b : row==2 ? c : {1'b0,vol};
            case(level)
                0:percent=12'h000;1:percent=12'h025;2:percent=12'h050;
                3:percent=12'h075;4:percent=12'h100;5:percent=12'h125;
                6:percent=12'h150;7:percent=12'h175;default:percent=12'h200;
            endcase
            case(period)
                0:seconds=8'h03;1:seconds=8'h05;2:seconds=8'h10;default:seconds=8'h15;
            endcase
            size=index<4 ? w : h;
            case(index)
                0,5:digit=size[15:12];1,6:digit=size[11:8];
                2,7:digit=size[7:4];default:digit=size[3:0];
            endcase
            value_char=" ";
            if(row==0) begin
                if(index==4) value_char="x";
                else if(index<9) begin
                    if(size==0) value_char="-";
                    else if((index==0 || index==5) && digit==0) value_char=" ";
                    else value_char="0"+digit;
                end
            end else if(row==3) begin
                case(index)
                    0:value_char="0"+seconds[7:4];
                    1:value_char="0"+seconds[3:0];
                    default:value_char=" ";
                endcase
            end else begin
                case(index)
                    0:value_char="0"+percent[11:8];
                    1:value_char="0"+percent[7:4];
                    2:value_char="0"+percent[3:0];
                    3:value_char="%";
                    default:value_char=" ";
                endcase
            end
        end
    endfunction
    function [15:0] second_scan;
        input [3:0] line_y;
        begin
            case(line_y)
                4'd0:second_scan=16'h0820;
                4'd1:second_scan=16'h1C20;
                4'd2:second_scan=16'hF020;
                4'd3:second_scan=16'h10A8;
                4'd4:second_scan=16'h10A4;
                4'd5:second_scan=16'hFCA2;
                4'd6:second_scan=16'h1122;
                4'd7:second_scan=16'h3120;
                4'd8:second_scan=16'h3A24;
                4'd9:second_scan=16'h5424;
                4'd10:second_scan=16'h5428;
                4'd11:second_scan=16'h9008;
                4'd12:second_scan=16'h1010;
                4'd13:second_scan=16'h1020;
                4'd14:second_scan=16'h10C0;
                4'd15:second_scan=16'h1300;
                default:second_scan=0;
            endcase
        end
    endfunction
    function [63:0] compact_label_scan;
        input [2:0] row;
        input [3:0] line_y;
        begin
            case({row,line_y})
                7'd0:compact_label_scan=64'h1104500400000000;
                7'd1:compact_label_scan=64'h110248FFE0000000;
                7'd2:compact_label_scan=64'h208F5C0800000000;
                7'd3:compact_label_scan=64'h2080405140000000;
                7'd4:compact_label_scan=64'h4045543E80000000;
                7'd5:compact_label_scan=64'hBFA2C80400000000;
                7'd6:compact_label_scan=64'h088F7E2A80000000;
                7'd7:compact_label_scan=64'h0882485F40000000;
                7'd8:compact_label_scan=64'h10875C0400000000;
                7'd9:compact_label_scan=64'h108248FFE0000000;
                7'd10:compact_label_scan=64'h2082480400000000;
                7'd11:compact_label_scan=64'h4704880400000000;
                7'd16:compact_label_scan=64'h0400200000000000;
                7'd17:compact_label_scan=64'hFFE7FE0000000000;
                7'd18:compact_label_scan=64'h0004880000000000;
                7'd19:compact_label_scan=64'h3F87FE0000000000;
                7'd20:compact_label_scan=64'h2084880000000000;
                7'd21:compact_label_scan=64'h3F84F80000000000;
                7'd22:compact_label_scan=64'h0004000000000000;
                7'd23:compact_label_scan=64'hFFE5FC0000000000;
                7'd24:compact_label_scan=64'h8024840000000000;
                7'd25:compact_label_scan=64'h3F04480000000000;
                7'd26:compact_label_scan=64'h2124300000000000;
                7'd27:compact_label_scan=64'hC0E9CE0000000000;
                7'd32:compact_label_scan=64'h0044200200000000;
                7'd33:compact_label_scan=64'h0044207FE0000000;
                7'd34:compact_label_scan=64'hF844224880000000;
                7'd35:compact_label_scan=64'h0BE4247FE0000000;
                7'd36:compact_label_scan=64'h0847A84880000000;
                7'd37:compact_label_scan=64'h8844304F80000000;
                7'd38:compact_label_scan=64'h5244204000000000;
                7'd39:compact_label_scan=64'h5144205FC0000000;
                7'd40:compact_label_scan=64'h2144A04840000000;
                7'd41:compact_label_scan=64'h5045224480000000;
                7'd42:compact_label_scan=64'h4846224300000000;
                7'd43:compact_label_scan=64'h89C41E9CE0000000;
                7'd48:compact_label_scan=64'h21041C3FE4800000;
                7'd49:compact_label_scan=64'h2105E020249E0000;
                7'd50:compact_label_scan=64'hF28524222FD20000;
                7'd51:compact_label_scan=64'h444EA82FA4920000;
                7'd52:compact_label_scan=64'h6825FE22279E0000;
                7'd53:compact_label_scan=64'hA404A83FE4920000;
                7'd54:compact_label_scan=64'hF447042027920000;
                7'd55:compact_label_scan=64'h258DFE2FA49E0000;
                7'd56:compact_label_scan=64'h36052428AFD20000;
                7'd57:compact_label_scan=64'hE425FC2FA0120000;
                7'd58:compact_label_scan=64'h2425244024920000;
                7'd59:compact_label_scan=64'h23EDFC80E8660000;
                7'd64:compact_label_scan=64'h0407FC0000000000;
                7'd65:compact_label_scan=64'h7FC4440000000000;
                7'd66:compact_label_scan=64'h2084240000000000;
                7'd67:compact_label_scan=64'h110FFE0000000000;
                7'd68:compact_label_scan=64'hFFE4440000000000;
                7'd69:compact_label_scan=64'h0007FC0000000000;
                7'd70:compact_label_scan=64'h7FC4440000000000;
                7'd71:compact_label_scan=64'h4047FC0000000000;
                7'd72:compact_label_scan=64'h7FC0400000000000;
                7'd73:compact_label_scan=64'h4047FC0000000000;
                7'd74:compact_label_scan=64'h7FC0400000000000;
                7'd75:compact_label_scan=64'h404FFE0000000000;
                default:compact_label_scan=0;
            endcase
        end
    endfunction
    function [15:0] compact_second_scan;
        input [3:0] line_y;
        begin
            case(line_y)
                4'd0:compact_second_scan=16'h1100;
                4'd1:compact_second_scan=16'hE100;
                4'd2:compact_second_scan=16'h2140;
                4'd3:compact_second_scan=16'h2520;
                4'd4:compact_second_scan=16'hF520;
                4'd5:compact_second_scan=16'h2520;
                4'd6:compact_second_scan=16'h6900;
                4'd7:compact_second_scan=16'h7120;
                4'd8:compact_second_scan=16'hA040;
                4'd9:compact_second_scan=16'h2080;
                4'd10:compact_second_scan=16'h2300;
                4'd11:compact_second_scan=16'h2C00;
                default:compact_second_scan=0;
            endcase
        end
    endfunction
    wire menu=active[10];
    wire panel=menu ? (px>=116 && px<524 && y>=112 && y<368) :
                     (px>=8 && px<136 && y>=8 && y<88);
    wire [9:0] dx=menu ? px-10'd132 : px-10'd12;
    wire [8:0] dy=menu ? y-9'd128 : y-9'd12;
    wire [9:0] lx=menu ? {1'b0,dx[9:1]} : dx;
    wire [8:0] ly=menu ? {1'b0,dy[8:1]} : dy;
    wire [4:0] step_y=menu ? 5'd24 : 5'd14;
    wire [2:0] row=ly<step_y ? 0 : ly<2*step_y ? 1 : ly<3*step_y ? 2 : ly<4*step_y ? 3 : 4;
    reg [8:0] row_y;
    always @* begin
        case(row)
            0:row_y=ly;1:row_y=ly-step_y;2:row_y=ly-2*step_y;
            3:row_y=ly-3*step_y;default:row_y=ly-4*step_y;
        endcase
    end
    wire letters=panel && row_y<(menu ? 16 : 12);
    wire [63:0] label_bits=menu ? label_scan(row,row_y[3:0]) : compact_label_scan(row,row_y[3:0]);
    wire label_ink=letters && lx<(menu ? 64 : 48) && label_bits[63-lx[5:0]];
    wire [9:0] vx=lx-(menu ? 10'd72 : 10'd54);
    wire [3:0] ci=menu ? vx/12 : vx/6;
    wire [3:0] cx=menu ? (vx%12)>>1 : vx%6;
    wire [2:0] cy=menu ? row_y[3:1] : row_y[3:0]-4'd2;
    wire [34:0] bits=glyph(value_char(row,ci,bright,contrast,active[12:11],volume,width_digits,height_digits));
    wire value_ink=letters && lx>=(menu ? 72 : 54) && lx<(menu ? 180 : 108) &&
                   (menu || (row_y>=2 && row_y<9)) && cx<5 && cy<7 && bits[(6-cy)*5+(4-cx)];
    // The period unit uses the same Chinese bitmap font as the labels.
    wire [15:0] second_bits=menu ? second_scan(row_y[3:0]) : compact_second_scan(row_y[3:0]);
    wire [9:0] second_x=lx-(menu ? 10'd100 : 10'd68);
    wire second_ink=letters && row==3 && lx>=(menu ? 100 : 68) && lx<(menu ? 116 : 80) && second_bits[15-second_x];
    wire ink=label_ink || value_ink || second_ink;
    wire selected=menu && row==({1'b0,active[9:8]}+3'd1);
    always @(posedge clk or posedge rst) begin
        if(rst) begin
            request_sync<=0;active<=16'h8044;settings_ack<=0;
            de_d<=0;vs_d<=0;x<=0;y<=0;
            hs_out<=0;vs_out<=0;de_out<=0;rgb_out<=0;
        end else begin
            request_sync<={request_sync[0],settings_toggle};de_d<=de;vs_d<=vs;
            if(vs_d && !vs) begin
                y<=0;
                if(request_sync[1]!=settings_ack) begin active<=settings_bundle;settings_ack<=request_sync[1];end
            end else if(de_d && !de) y<=y+1'b1;
            if(de) x<=px+1'b1;else x<=0;
            hs_out<=hs;vs_out<=vs;de_out<=de;
            rgb_out<=!de ? 24'd0 : !panel ? rgb :
                ink ? (selected ? 24'hffe060 : 24'hffffff) :
                {2'b0,rgb[23:18],2'b0,rgb[15:10],2'b0,rgb[7:2]};
        end
    end
endmodule
