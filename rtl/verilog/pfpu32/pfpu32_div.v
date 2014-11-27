//////////////////////////////////////////////////////////////////////
//                                                                  //
//    pfpu32_div                                                    //
//                                                                  //
//    This file is part of the mor1kx project                       //
//    https://github.com/openrisc/mor1kx                            //
//                                                                  //
//    Description                                                   //
//    divider pipeline for single precision floating                //
//    point numbers                                                 //
//                                                                  //
//    Author(s):                                                    //
//        - Original design (FPU100) -                              //
//          Jidan Al-eryani, jidan@gmx.net                          //
//        - Conv. to Verilog and inclusion in OR1200 -              //
//          Julius Baxter, julius@opencores.org                     //
//        - Update for mor1kx,                                      //
//          bug fixing and further development -                    //
//          Andrey Bacherov, avbacherov@opencores.org               //
//                                                                  //
//////////////////////////////////////////////////////////////////////
//                                                                  //
//  Copyright (C) 2006, 2010, 2014                                  //
//                                                                  //
//  This source file may be used and distributed without            //
//  restriction provided that this copyright statement is not       //
//  removed from the file and that any derivative work contains     //
//  the original copyright notice and the associated disclaimer.    //
//                                                                  //
//    THIS SOFTWARE IS PROVIDED ``AS IS'' AND WITHOUT ANY           //
//  EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED       //
//  TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS       //
//  FOR A PARTICULAR PURPOSE. IN NO EVENT SHALL THE AUTHOR          //
//  OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT,             //
//  INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES        //
//  (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE       //
//  GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR            //
//  BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF      //
//  LIABILITY, WHETHER IN  CONTRACT, STRICT LIABILITY, OR TORT      //
//  (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT      //
//  OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE             //
//  POSSIBILITY OF SUCH DAMAGE.                                     //
//////////////////////////////////////////////////////////////////////

`include "mor1kx-defines.v"

//`define NEW_F32_DIV

module pfpu32_div
(
   input             clk,
   input             rst,
   input             flush_i,  // flushe pipe
   input             adv_i,    // advance pipe
   input             start_i,  // start division
   input             signa_i,  // input 'a' related values
   input       [9:0] exp10a_i,
   input      [23:0] fract24a_i,
   input             infa_i,
   input             zeroa_i,
   input             signb_i,  // input 'b' related values
   input       [9:0] exp10b_i,
   input      [23:0] fract24b_i,
   input             infb_i,
   input             zerob_i,
   input             snan_i,   // 'a'/'b' related
   input             qnan_i,
   input             anan_sign_i,
   output reg        div_rdy_o,       // div is ready
   output reg        div_sign_o,      // div signum
   output reg  [9:0] div_exp10_o,     // div exponent
   output reg [23:0] div_fract24_o,   // div fractional
   output reg  [1:0] div_rs_o,        // div round & sticky bits
   output reg        div_inv_o,       // div invalid operation flag
   output reg        div_inf_o,       // div infinity output reg
   output reg        div_snan_o,      // div signaling NaN output reg
   output reg        div_qnan_o,      // div quiet NaN output reg
   output reg        div_anan_sign_o, // div signum for output nan
   output reg        div_dbz_o,       // div division by zero flag
   output reg        div_dbinf_o      // div division by infinity
);

  /*
     Any stage's output is registered.
     Definitions:
       s??o_name - "S"tage number "??", "O"utput
       s??t_name - "S"tage number "??", "T"emporary (internally)
  */


  /* Stage #1: pre-division normalization */

    // detection of some exceptions
    //   0/0, inf/inf -> invalid operation; snan output
  wire s1t_inv = (zeroa_i & zerob_i) | (infa_i & infb_i);
    // division by zero and infinity
  wire s1t_dbz   = (!zeroa_i) & (!infa_i) & zerob_i;
  wire s1t_dbinf = (!zeroa_i) & (!infa_i) & infb_i;
    //   inf input
  wire s1t_inf_i = infa_i;

  // force intermediate results to zero
  wire s1t_fz = zeroa_i | zerob_i | infa_i| infb_i;
  wire [23:0] s1t_fract24a_fz = fract24a_i & {24{!s1t_fz}};
  
  // count leading zeros
  reg [5:0] s1t_dvd_zeros;
  always @(s1t_fract24a_fz)
    casez(s1t_fract24a_fz) // synopsys full_case parallel_case
      24'b1???????????????????????: s1t_dvd_zeros =  0;
      24'b01??????????????????????: s1t_dvd_zeros =  1;
      24'b001?????????????????????: s1t_dvd_zeros =  2;
      24'b0001????????????????????: s1t_dvd_zeros =  3;
      24'b00001???????????????????: s1t_dvd_zeros =  4;
      24'b000001??????????????????: s1t_dvd_zeros =  5;
      24'b0000001?????????????????: s1t_dvd_zeros =  6;
      24'b00000001????????????????: s1t_dvd_zeros =  7;
      24'b000000001???????????????: s1t_dvd_zeros =  8;
      24'b0000000001??????????????: s1t_dvd_zeros =  9;
      24'b00000000001?????????????: s1t_dvd_zeros = 10;
      24'b000000000001????????????: s1t_dvd_zeros = 11;
      24'b0000000000001???????????: s1t_dvd_zeros = 12;
      24'b00000000000001??????????: s1t_dvd_zeros = 13;
      24'b000000000000001?????????: s1t_dvd_zeros = 14;
      24'b0000000000000001????????: s1t_dvd_zeros = 15;
      24'b00000000000000001???????: s1t_dvd_zeros = 16;
      24'b000000000000000001??????: s1t_dvd_zeros = 17;
      24'b0000000000000000001?????: s1t_dvd_zeros = 18;
      24'b00000000000000000001????: s1t_dvd_zeros = 19;
      24'b000000000000000000001???: s1t_dvd_zeros = 20;
      24'b0000000000000000000001??: s1t_dvd_zeros = 21;
      24'b00000000000000000000001?: s1t_dvd_zeros = 22;
      24'b000000000000000000000001: s1t_dvd_zeros = 23;
      24'b000000000000000000000000: s1t_dvd_zeros =  0; // zero rezult
    endcase

  // count leading zeros
  reg [5:0] s1t_div_zeros;
  always @(fract24b_i)
    casez(fract24b_i) // synopsys full_case parallel_case
      24'b1???????????????????????: s1t_div_zeros =  0;
      24'b01??????????????????????: s1t_div_zeros =  1;
      24'b001?????????????????????: s1t_div_zeros =  2;
      24'b0001????????????????????: s1t_div_zeros =  3;
      24'b00001???????????????????: s1t_div_zeros =  4;
      24'b000001??????????????????: s1t_div_zeros =  5;
      24'b0000001?????????????????: s1t_div_zeros =  6;
      24'b00000001????????????????: s1t_div_zeros =  7;
      24'b000000001???????????????: s1t_div_zeros =  8;
      24'b0000000001??????????????: s1t_div_zeros =  9;
      24'b00000000001?????????????: s1t_div_zeros = 10;
      24'b000000000001????????????: s1t_div_zeros = 11;
      24'b0000000000001???????????: s1t_div_zeros = 12;
      24'b00000000000001??????????: s1t_div_zeros = 13;
      24'b000000000000001?????????: s1t_div_zeros = 14;
      24'b0000000000000001????????: s1t_div_zeros = 15;
      24'b00000000000000001???????: s1t_div_zeros = 16;
      24'b000000000000000001??????: s1t_div_zeros = 17;
      24'b0000000000000000001?????: s1t_div_zeros = 18;
      24'b00000000000000000001????: s1t_div_zeros = 19;
      24'b000000000000000000001???: s1t_div_zeros = 20;
      24'b0000000000000000000001??: s1t_div_zeros = 21;
      24'b00000000000000000000001?: s1t_div_zeros = 22;
      24'b000000000000000000000001: s1t_div_zeros = 23;
      24'b000000000000000000000000: s1t_div_zeros =  0; // zero result
    endcase

  // left-shift the dividend and divisor
  wire [23:0] s1t_fracta_lshift_intermediate;
  wire [23:0] s1t_fractb_lshift_intermediate;
  assign s1t_fracta_lshift_intermediate = s1t_fract24a_fz << s1t_dvd_zeros;
  assign s1t_fractb_lshift_intermediate = fract24b_i << s1t_div_zeros;

  // stage #1 outputs
  //   input related
  reg s1o_inv, s1o_inf_i, s1o_dbz, s1o_dbinf, s1o_fz,
      s1o_snan_i, s1o_qnan_i, s1o_anan_i_sign;
  //   computation related
  reg s1o_sign;
  reg [9:0]  s1o_exp10;
  reg [49:0] s1o_dvdnd_50;
  reg [26:0] s1o_dvsor_27;

  //   registering
  always @(posedge clk) begin
    if(adv_i) begin
        // input related
      s1o_inv         <= s1t_inv;
      s1o_inf_i       <= s1t_inf_i;
      s1o_dbz         <= s1t_dbz;
      s1o_dbinf       <= s1t_dbinf;
      s1o_fz          <= s1t_fz;
      s1o_snan_i      <= snan_i;
      s1o_qnan_i      <= qnan_i;
      s1o_anan_i_sign <= anan_sign_i;
        // computation related
      s1o_sign     <= signa_i ^ signb_i;
      s1o_exp10    <= (exp10a_i - exp10b_i + 10'd127 -
                       {4'd0,s1t_dvd_zeros} + {4'd0,s1t_div_zeros})
                      & {10{!s1t_fz}};
      s1o_dvdnd_50 <= {s1t_fracta_lshift_intermediate,26'd0};
      s1o_dvsor_27 <= {3'd0,s1t_fractb_lshift_intermediate};
    end // advance
  end // posedge clock

  // ready is special case
  reg s1o_ready;
  always @(posedge clk `OR_ASYNC_RST) begin
    if (rst)
      s1o_ready <= 0;
    else if(flush_i)
      s1o_ready <= 0;
    else if(adv_i)
      s1o_ready <= start_i;
  end // posedge clock


  /* Stage #2: division */

  localparam STATE_WAITING = 1'b0,
             STATE_BUSY    = 1'b1;

  reg       s2t_ready;
  reg       s2t_state;
  reg [4:0] s2t_count;

  always @(posedge clk `OR_ASYNC_RST) begin
    if (rst) begin
      s2t_state <= STATE_WAITING;
      s2t_ready <= 1'b0;
    end
    else if(flush_i) begin
      s2t_state <= STATE_WAITING;
      s2t_ready <= 1'b0;
    end
    else if (s1o_ready & adv_i) begin
      s2t_state <= STATE_BUSY;
      s2t_count <= 5'd26;
    end
    else if ((!(|s2t_count) & s2t_state==STATE_BUSY) & adv_i) begin
      s2t_state <= STATE_WAITING;
      s2t_ready <= 1'b1;
      s2t_count <= 5'd26;
    end
    else if ((s2t_state==STATE_BUSY) & adv_i)
      s2t_count <= s2t_count - 5'd1;
    else if(adv_i) begin
      s2t_state <= STATE_WAITING;
      s2t_ready <= 1'b0;
    end
  end // posedge clock

  reg  [26:0] s2t_qutnt;
  reg  [26:0] s2t_rmndr;
  reg  [26:0] s2t_dvd;

  wire [26:0] v2t_div;
  wire [26:0] v2t_div_minus_s1o_dvsor_27;

  assign v2t_div = (s2t_count==5'd26) ? {3'd0,s1o_dvdnd_50[49:26]} : s2t_dvd;
  assign v2t_div_minus_s1o_dvsor_27 = v2t_div - s1o_dvsor_27;

  always @(posedge clk `OR_ASYNC_RST) begin
    if(rst) begin
      s2t_qutnt <= 1'b0;
      s2t_rmndr <= 1'b0;
    end
    else if (flush_i) begin
      s2t_qutnt <= 1'b0;
      s2t_rmndr <= 1'b0;
    end
    else if (s1o_ready & adv_i) begin
      s2t_qutnt <= 1'b0;
      s2t_rmndr <= 1'b0;
    end
    else if ((s2t_state==STATE_BUSY) & adv_i) begin
      if (v2t_div < s1o_dvsor_27) begin
        s2t_qutnt[s2t_count] <= 1'b0;
        s2t_dvd <= {v2t_div[25:0],1'b0};
      end
      else begin
        s2t_qutnt[s2t_count] <= 1'b1;
        s2t_dvd <= {v2t_div_minus_s1o_dvsor_27[25:0],1'b0};
      end

      s2t_rmndr <= v2t_div;
    end // if (s2t_state==STATE_BUSY)
  end // posedge

  // stage #2 outputs
  //   input related
  reg s2o_inv, s2o_inf_i, s2o_dbz, s2o_dbinf, s2o_fz,
      s2o_snan_i, s2o_qnan_i, s2o_anan_i_sign;
  //   computation related
  reg        s2o_sign;
  reg [9:0]  s2o_exp10;
  reg [25:0] s2o_qutnt;

  //   registering
  always @(posedge clk) begin
    if(adv_i) begin
        // input related
      s2o_inv         <= s1o_inv;
      s2o_inf_i       <= s1o_inf_i;
      s2o_dbz         <= s1o_dbz;
      s2o_dbinf       <= s1o_dbinf;
      s2o_fz          <= s1o_fz;
      s2o_snan_i      <= s1o_snan_i;
      s2o_qnan_i      <= s1o_qnan_i;
      s2o_anan_i_sign <= s1o_anan_i_sign;
        // computation related
      s2o_sign  <= s1o_sign;
      s2o_exp10 <= s1o_exp10;
      s2o_qutnt <= {s2t_qutnt[26:2],((|s2t_qutnt[1:0]) | (|s2t_rmndr))}
                   & {26{!s1o_fz}};
    end // (reset or flush) / advance
  end // posedge clock

  // ready is special case
  reg s2o_ready;
  always @(posedge clk `OR_ASYNC_RST) begin
    if (rst)
      s2o_ready <= 0;
    else if(flush_i)
      s2o_ready <= 0;
    else if(adv_i)
      s2o_ready <= s2t_ready;
  end // posedge clock


  /* Stage #3: calc align values */  

  // qutnt
  // 25 24                    2
  // |  |                     |
  // h  fffffffffffffffffffffff rs

  // rigt shift value
  // and appropriatelly corrected exponent
  wire s2o_exp10_0 = !(|s2o_exp10);
  wire [9:0] s3t_shr_of_neg_exp = 11'h401 - {1'b0,s2o_exp10}; // 1024-v+1
  //...
  wire [9:0] s3t_shrx;
  wire [9:0] s3t_exp10rx;
  assign {s3t_shrx,s3t_exp10rx} =
      // zero result case
    s2o_fz                  ? {10'd0,10'd0} :
      // zero exponent sum (denorm. result potentially)
    (!s2o_fz & s2o_exp10_0) ? {10'd1,10'd1} :
      // negative exponent sum
      //  (!) takes carry into account automatically
    s2o_exp10[9]            ? {s3t_shr_of_neg_exp,10'd1} :
      // normal case at last
                              {10'd0,s2o_exp10};
  // max. right shift that makes sense is 25bits
  //  i.e. [25] moves to sticky position: ([0])
  wire [5:0] s3t_shr = (s3t_shrx > 10'd25) ? 6'd25 : s3t_shrx[5:0];

  // in fact, as the dividend and divisor was normalized
  // and the result is non-zero
  // the '1' is maximum number of leading zeros in the quotient
  wire s3t_nlz = !s2o_qutnt[25];
    //...
  wire [9:0] s3t_exp10_m1 = s2o_exp10 - 10'd1;
  // left shift flag and corrected exponent
  wire       s3t_shlx;
  wire [9:0] s3t_exp10lx;
  assign {s3t_shlx,s3t_exp10lx} =
      // shift isn't needed (includes zero result)
    (!s3t_nlz)           ? {1'b0,s2o_exp10} :
      // normalization is possible
    (s2o_exp10 >  10'd1) ? {1'b1,s3t_exp10_m1} :
      // denormalized cases
                           {1'b0,10'd1};

  // align
  wire [25:0] s3t_fract26 =
    (|s3t_shr) ? (s2o_qutnt >> s3t_shr) :
                 (s2o_qutnt << s3t_shlx);

  // sticky bit computation for right shift
  // max. right shift that makes sense i 25bits
  //  i.e. [25] moves to sticky position: ([0])
  reg s3t_sticky_shr;
  always @(s3t_shr or s2o_qutnt) begin
    case(s3t_shr)
      6'd0   : s3t_sticky_shr =  s2o_qutnt[   0];
      6'd1   : s3t_sticky_shr = |s2o_qutnt[ 1:0];
      6'd2   : s3t_sticky_shr = |s2o_qutnt[ 2:0];
      6'd3   : s3t_sticky_shr = |s2o_qutnt[ 3:0];
      6'd4   : s3t_sticky_shr = |s2o_qutnt[ 4:0];
      6'd5   : s3t_sticky_shr = |s2o_qutnt[ 5:0];
      6'd6   : s3t_sticky_shr = |s2o_qutnt[ 6:0];
      6'd7   : s3t_sticky_shr = |s2o_qutnt[ 7:0];
      6'd8   : s3t_sticky_shr = |s2o_qutnt[ 8:0];
      6'd9   : s3t_sticky_shr = |s2o_qutnt[ 9:0];
      6'd10  : s3t_sticky_shr = |s2o_qutnt[10:0];
      6'd11  : s3t_sticky_shr = |s2o_qutnt[11:0];
      6'd12  : s3t_sticky_shr = |s2o_qutnt[12:0];
      6'd13  : s3t_sticky_shr = |s2o_qutnt[13:0];
      6'd14  : s3t_sticky_shr = |s2o_qutnt[14:0];
      6'd15  : s3t_sticky_shr = |s2o_qutnt[15:0];
      6'd16  : s3t_sticky_shr = |s2o_qutnt[16:0];
      6'd17  : s3t_sticky_shr = |s2o_qutnt[17:0];
      6'd18  : s3t_sticky_shr = |s2o_qutnt[18:0];
      6'd19  : s3t_sticky_shr = |s2o_qutnt[19:0];
      6'd20  : s3t_sticky_shr = |s2o_qutnt[20:0];
      6'd21  : s3t_sticky_shr = |s2o_qutnt[21:0];
      6'd22  : s3t_sticky_shr = |s2o_qutnt[22:0];
      6'd23  : s3t_sticky_shr = |s2o_qutnt[23:0];
      6'd24  : s3t_sticky_shr = |s2o_qutnt[24:0];
      default: s3t_sticky_shr = |s2o_qutnt[25:0];
    endcase
  end // always

  wire s3t_sticky = (|s3t_shr) ? s3t_sticky_shr : s3t_fract26[0];


  // registering output
  always @(posedge clk) begin
    if(adv_i) begin
        // input related
      div_inv_o       <= s2o_inv;
      div_inf_o       <= s2o_inf_i;
      div_dbz_o       <= s2o_dbz;
      div_dbinf_o     <= s2o_dbinf;
      div_snan_o      <= s2o_snan_i;
      div_qnan_o      <= s2o_qnan_i;
      div_anan_sign_o <= s2o_anan_i_sign;
        // computation related
      div_sign_o    <= s2o_sign;
      div_exp10_o   <= (|s3t_shr) ? s3t_exp10rx : s3t_exp10lx;
      div_fract24_o <= s3t_fract26[25:2];
      div_rs_o      <= {s3t_fract26[1],s3t_sticky};
    end // advance
  end // posedge clock

  // ready is special case
  always @(posedge clk `OR_ASYNC_RST) begin
    if (rst)
      div_rdy_o <= 0;
    else if(flush_i)
      div_rdy_o <= 0;
    else if(adv_i)
      div_rdy_o <= s2o_ready;
  end // posedge clock

endmodule // pfpu32_div
