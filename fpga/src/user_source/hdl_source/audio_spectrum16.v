// 512-sample partial DFT, bins 1..16 at 48 kHz (93.75..1500 Hz).
// One shared signed multiplier; the existing PCM source has >500 clocks between samples.
module audio_spectrum16(
    input wire clk,rst,enable,pcm_valid,
    input wire [23:0] pcm_left,
    output reg [127:0] levels,
    output reg levels_ready
);
    function signed [15:0] sine;
        input [8:0] angle;
        reg [7:0] index;
        reg signed [15:0] quarter;
        begin
            index=angle[7] ? 8'd128-{1'b0,angle[6:0]} : {1'b0,angle[6:0]};
            case(index)
                8'd0:quarter=16'sd0;
                8'd1:quarter=16'sd402;
                8'd2:quarter=16'sd804;
                8'd3:quarter=16'sd1206;
                8'd4:quarter=16'sd1608;
                8'd5:quarter=16'sd2009;
                8'd6:quarter=16'sd2410;
                8'd7:quarter=16'sd2811;
                8'd8:quarter=16'sd3212;
                8'd9:quarter=16'sd3612;
                8'd10:quarter=16'sd4011;
                8'd11:quarter=16'sd4410;
                8'd12:quarter=16'sd4808;
                8'd13:quarter=16'sd5205;
                8'd14:quarter=16'sd5602;
                8'd15:quarter=16'sd5998;
                8'd16:quarter=16'sd6393;
                8'd17:quarter=16'sd6786;
                8'd18:quarter=16'sd7179;
                8'd19:quarter=16'sd7571;
                8'd20:quarter=16'sd7962;
                8'd21:quarter=16'sd8351;
                8'd22:quarter=16'sd8739;
                8'd23:quarter=16'sd9126;
                8'd24:quarter=16'sd9512;
                8'd25:quarter=16'sd9896;
                8'd26:quarter=16'sd10278;
                8'd27:quarter=16'sd10659;
                8'd28:quarter=16'sd11039;
                8'd29:quarter=16'sd11417;
                8'd30:quarter=16'sd11793;
                8'd31:quarter=16'sd12167;
                8'd32:quarter=16'sd12539;
                8'd33:quarter=16'sd12910;
                8'd34:quarter=16'sd13279;
                8'd35:quarter=16'sd13645;
                8'd36:quarter=16'sd14010;
                8'd37:quarter=16'sd14372;
                8'd38:quarter=16'sd14732;
                8'd39:quarter=16'sd15090;
                8'd40:quarter=16'sd15446;
                8'd41:quarter=16'sd15800;
                8'd42:quarter=16'sd16151;
                8'd43:quarter=16'sd16499;
                8'd44:quarter=16'sd16846;
                8'd45:quarter=16'sd17189;
                8'd46:quarter=16'sd17530;
                8'd47:quarter=16'sd17869;
                8'd48:quarter=16'sd18204;
                8'd49:quarter=16'sd18537;
                8'd50:quarter=16'sd18868;
                8'd51:quarter=16'sd19195;
                8'd52:quarter=16'sd19519;
                8'd53:quarter=16'sd19841;
                8'd54:quarter=16'sd20159;
                8'd55:quarter=16'sd20475;
                8'd56:quarter=16'sd20787;
                8'd57:quarter=16'sd21096;
                8'd58:quarter=16'sd21403;
                8'd59:quarter=16'sd21705;
                8'd60:quarter=16'sd22005;
                8'd61:quarter=16'sd22301;
                8'd62:quarter=16'sd22594;
                8'd63:quarter=16'sd22884;
                8'd64:quarter=16'sd23170;
                8'd65:quarter=16'sd23452;
                8'd66:quarter=16'sd23731;
                8'd67:quarter=16'sd24007;
                8'd68:quarter=16'sd24279;
                8'd69:quarter=16'sd24547;
                8'd70:quarter=16'sd24811;
                8'd71:quarter=16'sd25072;
                8'd72:quarter=16'sd25329;
                8'd73:quarter=16'sd25582;
                8'd74:quarter=16'sd25832;
                8'd75:quarter=16'sd26077;
                8'd76:quarter=16'sd26319;
                8'd77:quarter=16'sd26556;
                8'd78:quarter=16'sd26790;
                8'd79:quarter=16'sd27019;
                8'd80:quarter=16'sd27245;
                8'd81:quarter=16'sd27466;
                8'd82:quarter=16'sd27683;
                8'd83:quarter=16'sd27896;
                8'd84:quarter=16'sd28105;
                8'd85:quarter=16'sd28310;
                8'd86:quarter=16'sd28510;
                8'd87:quarter=16'sd28706;
                8'd88:quarter=16'sd28898;
                8'd89:quarter=16'sd29085;
                8'd90:quarter=16'sd29268;
                8'd91:quarter=16'sd29447;
                8'd92:quarter=16'sd29621;
                8'd93:quarter=16'sd29791;
                8'd94:quarter=16'sd29956;
                8'd95:quarter=16'sd30117;
                8'd96:quarter=16'sd30273;
                8'd97:quarter=16'sd30424;
                8'd98:quarter=16'sd30571;
                8'd99:quarter=16'sd30714;
                8'd100:quarter=16'sd30852;
                8'd101:quarter=16'sd30985;
                8'd102:quarter=16'sd31113;
                8'd103:quarter=16'sd31237;
                8'd104:quarter=16'sd31356;
                8'd105:quarter=16'sd31470;
                8'd106:quarter=16'sd31580;
                8'd107:quarter=16'sd31685;
                8'd108:quarter=16'sd31785;
                8'd109:quarter=16'sd31880;
                8'd110:quarter=16'sd31971;
                8'd111:quarter=16'sd32057;
                8'd112:quarter=16'sd32137;
                8'd113:quarter=16'sd32213;
                8'd114:quarter=16'sd32285;
                8'd115:quarter=16'sd32351;
                8'd116:quarter=16'sd32412;
                8'd117:quarter=16'sd32469;
                8'd118:quarter=16'sd32521;
                8'd119:quarter=16'sd32567;
                8'd120:quarter=16'sd32609;
                8'd121:quarter=16'sd32646;
                8'd122:quarter=16'sd32678;
                8'd123:quarter=16'sd32705;
                8'd124:quarter=16'sd32728;
                8'd125:quarter=16'sd32745;
                8'd126:quarter=16'sd32757;
                8'd127:quarter=16'sd32765;
                8'd128:quarter=16'sd32767;
                default:quarter=0;
            endcase
            sine=angle[8] ? -quarter : quarter;
        end
    endfunction
    reg [2:0] state;
    reg [8:0] sample_index,phase;
    reg [3:0] bin;
    reg signed [15:0] sample_word;
    reg signed [31:0] product;
    reg signed [40:0] real_sum[0:15],imag_sum[0:15];
    reg [127:0] next_levels;
    wire [8:0] angle=state==1 ? phase+9'd128 : phase;
    wire signed [15:0] coefficient=sine(angle);
    wire signed [40:0] extended_product={{9{product[31]}},product};
    wire [40:0] abs_real=real_sum[bin][40] ? -real_sum[bin] : real_sum[bin];
    wire [40:0] abs_imag=imag_sum[bin][40] ? -imag_sum[bin] : imag_sum[bin];
    // shortcut: L1 magnitude and a rectangular window, adequate for the current tonal music;
    // use a window and calibrated power/log scale for general-purpose audio measurements.
    wire [41:0] magnitude={1'b0,abs_real}+{1'b0,abs_imag};
    wire [7:0] scaled=|magnitude[41:36] ? 8'd255 : magnitude[35:28];
    integer n;
    always @(posedge clk or posedge rst) begin
        if(rst) begin
            state<=0;sample_index<=0;phase<=0;bin<=0;sample_word<=0;product<=0;
            levels<=0;next_levels<=0;levels_ready<=0;
            for(n=0;n<16;n=n+1) begin real_sum[n]<=0;imag_sum[n]<=0;end
        end else if(!enable) begin
            state<=0;sample_index<=0;levels<=0;next_levels<=0;levels_ready<=0;
        end else begin
            case(state)
                0:if(pcm_valid) begin
                    sample_word<=$signed(pcm_left[23:8]);bin<=0;phase<=sample_index;state<=1;
                end
                1:begin product<=sample_word*coefficient;state<=2;end
                2:begin
                    real_sum[bin]<=(sample_index==0 ? 41'sd0 : real_sum[bin])+extended_product;
                    product<=sample_word*coefficient;state<=3;
                end
                3:begin
                    imag_sum[bin]<=(sample_index==0 ? 41'sd0 : imag_sum[bin])+extended_product;
                    if(bin==15) begin
                        if(sample_index==511) begin bin<=0;state<=4;end
                        else begin sample_index<=sample_index+1'b1;state<=0;end
                    end else begin bin<=bin+1'b1;phase<=phase+sample_index;state<=1;end
                end
                4:begin
                    next_levels[bin*8 +: 8]<=scaled;
                    if(bin==15) state<=5;else bin<=bin+1'b1;
                end
                5:begin levels_ready<=1;levels<=next_levels;sample_index<=0;state<=0;end
                default:state<=0;
            endcase
        end
    end
endmodule
