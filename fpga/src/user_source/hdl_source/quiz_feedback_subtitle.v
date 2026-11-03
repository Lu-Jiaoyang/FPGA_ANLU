module quiz_feedback_subtitle(
    input wire clk,rst,
    input wire hs,vs,de,
    input wire [23:0] rgb,
    input wire [3:0] active_page,
    input wire answer_correct,
    input wire learning_autoplay,
    output reg hs_out,vs_out,de_out,
    output reg [23:0] rgb_out,
    input wire [1:0] review_caption
);
    localparam [255:0] G0=256'h041004103FFE041004107FFF06101C883086C4C908A410A620920F0000000000;
    localparam [255:0] G1=256'h0100FFFE01007FFC00003FF820083FF80C20FFFE00003FF820083FF820080000;
    localparam [255:0] G2=256'h0880088011FF110112233222302050A451261322122314211020102011E00000;
    localparam [255:0] G3=256'h182030603F7E6890C5088288044018302FF8C0061FF8100810081FF810080000;
    localparam [255:0] G4=256'h000400047E04020442FF260434841C440C440C24160432046104807800000000;
    localparam [255:0] G5=256'h00007FFE000E0018006000C000800080008000800080008000800F0000000000;
    localparam [255:0] G6=256'h404027FC344417FC0040EFFE200027FC2444244424E421986E04D0008FFE0000;
    localparam [255:0] G7=256'h2014201237FE74106DF2A416A5FC25292DF928362340252A250929F100000000;
    localparam [255:0] G8=256'h208820887BFE40888088F7FE200023FCFA04220423FC2A043A0433FC22040000;

    function [255:0] glyph;
        input [3:0] id;
        begin
            case(id)
                0:glyph=G0;1:glyph=G1;2:glyph=G2;3:glyph=G3;4:glyph=G4;
                5:glyph=G5;6:glyph=G6;7:glyph=G7;8:glyph=G8;
                default:glyph=0;
            endcase
        end
    endfunction

    // 16x16 monochrome SimSun glyphs: FPGA科普互动学习系统.
    function [255:0] ticker_glyph;
        input [3:0] id;
        begin
            case(id)
                0:ticker_glyph=256'h000000000FC00420048004800780048004800400040004000E00000000000000;
                1:ticker_glyph=256'h000000000FC0042004200420042007C004000400040004000E00000000000000;
                2:ticker_glyph=256'h0000000003C00440044008000800080008E00840044004400380000000000000;
                3:ticker_glyph=256'h0000000001000100018002800280024003C00440042004200E70000000000000;
                4:ticker_glyph=256'h08101D10F09010901010FD10109038903410501E53F090101010101010101010;
                5:ticker_glyph=256'h082004407FFC044024481450FFFE00001FF0101010101FF0101010101FF01010;
                6:ticker_glyph=256'h00007FFC0400040004000FF008100810101010201FE0002000400040FFFE0000;
                7:ticker_glyph=256'h004000407C40004001FC0044FE4420442044208448844484FD04450402280410;
                8:ticker_glyph=256'h22081108111000207FFE400280041FE000400180FFFE01000100010005000200;
                9:ticker_glyph=256'h7FF8000800080808040802080208006801880E08700820080008005000200000;
                10:ticker_glyph=256'h00F83F000400082010403F800100061018087FFC010409201110210845040200;
                11:ticker_glyph=256'h10401020202023FE4840F888110423FE4092F890409000901912E112420E0400;
                default:ticker_glyph=0;
            endcase
        end
    endfunction

    // Four-character review messages reuse the existing left margin and 24x24 scaling.
    function [255:0] review_glyph;
        input [3:0] id;
        begin case(id)
            0:review_glyph=256'h21102110391027FC41107910AFFE2000FBF82208220823F82A08320823F80208;
            1:review_glyph=256'h3EFE22103E20227C3E440054FF54085408542F282844288258004FFE80000000;
            2:review_glyph=256'h00003FF82008200827C82448244824482448244827C8200820083FF820080000;
            3:review_glyph=256'h7EFE402040405EFC5284529452945A945494509452A454305848508483020000;
            4:review_glyph=256'h0100010002800440082010102FE8C106010001001FF00100010001007FFC0000;
            5:review_glyph=256'h1000083E7FA2002421241228FFE4002400223F222122213421283F2021200020;
            6:review_glyph=256'h111009203FFC20044FE808200FE000F03F0001003FF801007FFC010005000200;
            7:review_glyph=256'h200023FC22042204FBFC220023FC2A403288E3FC2224222025FC2420A82053FE;
            8:review_glyph=256'h020001007FFE400280041FF0000000007FFC044004400440084408441044603C;
            9:review_glyph=256'h0050004800403FFE2040204020443E4422442228222822122A32444A40868102;
            default:review_glyph=0;
        endcase end
    endfunction
    (* async_reg="true" *) reg [1:0] review_meta,review_sync;
    reg [1:0] review_frame;
    (* async_reg="true" *) reg [1:0] correct_sync;
    (* async_reg="true" *) reg [1:0] autoplay_sync;
    reg ticker_active;
    reg [9:0] ticker_offset;
    reg [3:0] page_q;
    reg [1:0] feedback;
    reg vs_q,de_q;
    reg [9:0] x;
    reg [8:0] y;
    wire frame_start=vs_q && !vs;
    wire [9:0] px=de_q ? x : 10'd0;
    wire answer_page=active_page>=9 && active_page<=12;
    wire question_page=active_page>=5 && active_page<=8;
    wire [9:0] tx=px-10'd1;
    wire [8:0] ty=y-9'd150;
    wire in_text=(review_frame!=0 || (feedback!=0 && answer_page)) &&
        px>=1 && px<(review_frame!=0 ? 53 : 79) && y>=150 && y<202;
    wire [1:0] cell_x=tx/26;
    wire [0:0] cell_y=ty/26;
    wire [3:0] glyph_id=feedback==1 ?
        (cell_y ? (cell_x==0 ? 3 : cell_x==1 ? 4 : 5) :
                  (cell_x==0 ? 0 : cell_x==1 ? 1 : cell_x==2 ? 2 : 0)) :
        (cell_y ? (cell_x==0 ? 3 : cell_x==1 ? 8 : cell_x==2 ? 5 : 0) :
                  (cell_x==0 ? 6 : cell_x==1 ? 7 : cell_x==2 ? 2 : 0));
    // Scale 16x16 to 24x24; keep the two-pixel spacing outside the glyph.
    wire [4:0] cell_pixel_x=tx%26;
    wire [4:0] cell_pixel_y=ty%26;
    wire [4:0] glyph_x=(cell_pixel_x*2)/3;
    wire [4:0] glyph_y=(cell_pixel_y*2)/3;
    wire [3:0] review_id=review_frame==1 ? {2'b0,cell_y,cell_x[0]} :
        review_frame==2 ? 4'd4+{2'b0,cell_y,cell_x[0]} :
        (cell_y ? 4'd8 : 4'd2)+{3'd0,cell_x[0]};
    wire [255:0] glyph_bits=glyph(glyph_id);
    wire [255:0] review_bits=review_glyph(review_id);
    wire [23:0] caption_color=review_frame==1 ? 24'hffe060 : review_frame==2 ? 24'h20ff70 :
        review_frame==3 ? 24'hffffff : feedback==1 ? 24'h20ff70 : 24'hff4040;
    wire glyph_pixel=in_text && glyph_x<16 && glyph_y<16 &&
        (review_frame!=0 ? review_bits[255-glyph_y*16-glyph_x] :
                           glyph_bits[255-glyph_y*16-glyph_x]);

    // The four learning images end their text above y450; retain their bottom border.
    wire ticker_band=ticker_active && y>=450 && y<470;
    wire [10:0] ticker_x={1'b0,px}+{1'b0,ticker_offset}-11'd640;
    wire [3:0] ticker_id=ticker_x/18;
    wire [4:0] ticker_col=ticker_x%18;
    wire [8:0] ticker_row=y-9'd452;
    wire [255:0] ticker_bits=ticker_glyph(ticker_id);
    wire ticker_ink=ticker_band && ticker_x<216 && ticker_col<16 && ticker_row<16 &&
        ticker_bits[255-ticker_row*16-ticker_col];

    always @(posedge clk or posedge rst) begin
        if(rst) begin
            correct_sync<=0;page_q<=0;feedback<=0;vs_q<=0;de_q<=0;x<=0;y<=0;
            autoplay_sync<=0;ticker_active<=0;ticker_offset<=0;
            review_meta<=0;review_sync<=0;review_frame<=0;
            hs_out<=0;vs_out<=0;de_out<=0;rgb_out<=0;
        end else begin
            correct_sync<={correct_sync[0],answer_correct};
            review_meta<=review_caption;review_sync<=review_meta;
            autoplay_sync<={autoplay_sync[0],learning_autoplay};
            vs_q<=vs;de_q<=de;
            if(frame_start) begin
                y<=0;review_frame<=review_sync;
                ticker_active<=autoplay_sync[1] && active_page>=1 && active_page<=4;
                if(!ticker_active || !autoplay_sync[1] || active_page<1 || active_page>4)
                    ticker_offset<=0;
                else if(ticker_offset==855) ticker_offset<=0;
                else ticker_offset<=ticker_offset+1'b1;
                if(active_page!=page_q) begin
                    page_q<=active_page;
                    if(answer_page) feedback<=correct_sync[1] ? 1 : 2;
                    else if(question_page) feedback<=0;
                end
            end else if(de_q && !de) y<=y+1'b1;
            if(de) x<=px+1'b1;else x<=0;
            hs_out<=hs;vs_out<=vs;de_out<=de;
            rgb_out<=!de ? 24'd0 : glyph_pixel ? caption_color :
                ticker_ink ? 24'hffffff :
                (in_text || ticker_band) ? 24'h101820 : rgb;
        end
    end
endmodule
