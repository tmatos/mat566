
module custom_logic_top(

   input clk_input,
   input rst_n_input,

   output master_clk,
   output master_rst_n,

   output reg master_read,
   output reg master_write,

   output reg [9:0] master_address,

   input [31:0] master_readdata,
   output reg [31:0] master_writedata,

   input master_waitrequest,
   output [3:0] master_byteen,

   input [31:0] command_port,
   output reg [31:0] status_port,

   input [17:0] switch_entrada_input,
   output [31:0] debug
   );

wire clk;
wire rst_n;

assign clk = clk_input;
assign rst_n = rst_n_input;

// para a interface avalon
assign master_clk = clk_input;
assign master_rst_n = (rst_n_input & resetn_interno_reg);
assign master_byteen = 4'b1111;

// Estados da FSM (codificados em one-hot)
parameter AGUARDANDO        = 8'b00000001,
          LEITURA_INICIAR   = 8'b00000010,
          LEITURA_LOOP      = 8'b00000100,
          OPERACAO_INICIAR  = 8'b00001000,
          OPERACAO_ESPERAR  = 8'b00010000,
          ESCRITA_RESULTADO = 8'b00100000,
          CONCLUIDO         = 8'b01000000;

// NUMERO DE AMOSTRAS DO BLOCO DE DADOS
parameter SIZE = 16'd40;

reg [7:0] estado;
reg [15:0] cnt;

reg cmd_executar;

reg enable_calcular;
reg reset_filtro;

reg resetn_interno_reg;

reg [31:0] mem [0:2047];

reg [31:0] in_sample; // SEM USO

// controlador baseado em FSM
always@(posedge clk) begin
   ////master_write <= 0;
   ////master_address <= 0;

   cmd_executar <= command_port[0];

   if(~rst_n) begin  // reset
      estado <= AGUARDANDO;
      resetn_interno_reg <= 1;
      in_sample <= 32'd0; // SEM USO
      enable_calcular <= 0;
   end
   else begin
      case(estado)
         AGUARDANDO:
            begin 
               if(cmd_executar) begin
                  estado <= LEITURA_LOOP;
                  master_write <= 0;
                  master_read <= 1;
                  master_address <= 0;
                  cnt <= 0;
                  status_port <= 0;
                  reset_filtro <= 1;
               end
               else begin
                  estado <= AGUARDANDO;
                  master_write <= 0;
                  master_read <= 0;
                  enable_calcular <= 0;
                  reset_filtro <= 0;
               end
            end
         LEITURA_LOOP:
            begin
               master_write <= 0;
               master_read <= 1;
               master_address <= cnt*4;
               
               in_sample <= master_readdata; // SEM USO
               mem[cnt] <= master_readdata;
               
               reset_filtro <= 0;

               if( cnt == (SIZE-1) ) begin
                  estado <= OPERACAO_ESPERAR;
                  master_write <= 0;
                  master_read <= 0;
                  master_address <= 0;
                  cnt <= 0;
                  enable_calcular <= 1;
               end
               else begin
                  estado <= LEITURA_LOOP;
                  cnt <= cnt+1;
               end
            end
         OPERACAO_ESPERAR: // DA PRA MESCLAR ESSA COM O ABAIXO
            begin
               if( cnt == (SIZE-1) ) begin
                  estado <= ESCRITA_RESULTADO;
                  master_write <= 1;
                  master_read <= 0;
                  master_address <= 512;
                  cnt <= 0;
                  enable_calcular <= 0;
               end
               else begin
                  estado <= OPERACAO_ESPERAR;
                  cnt <= cnt+1;
                  enable_calcular <= 1;
               end
            end
         ESCRITA_RESULTADO: // DA PRA MESCLAR ESSA COM O ACIMA
            begin
               if( cnt == (SIZE-1) ) begin
                  estado <= CONCLUIDO;
                  master_write <= 0;
                  master_read <= 0;
                  master_address <= 0;
                  cnt <= 0;
                  master_writedata <= 0;
               end
               else begin
                  estado <= ESCRITA_RESULTADO;
                  master_write <= 1;
                  master_read <= 0;
                  master_address <= 512+cnt*4;
                  cnt <= cnt+1;
                  master_writedata <= mem[512+cnt];
               end
            end
         CONCLUIDO:
            begin
               status_port <= 32'd1; // indica conclusao ao processo
               resetn_interno_reg <= 0; // isso e necessario para destravar o app (nao sei pq)
               if(~cmd_executar)
                  estado <= AGUARDANDO;
               else
                  estado <= CONCLUIDO;
            end
         default:
            estado <= AGUARDANDO;
      endcase
   end

   filtro f0 ( .clk(clk),
               .reset( ~rst_n_input | reset_filtro ),
               .enable(enable_calcular),
               .entrada( mem[cnt] ),
               .saida( mem[512+cnt] )
             );

end

/*************************************************************/
// Debug Data
/*************************************************************/
wire [7:0] debug_b3, debug_b2, debug_b1, debug_b0;

assign debug_b0 = 8'd0;
assign debug_b1 = 8'd0;
assign debug_b2 = 8'd0;
assign debug_b3 = {rst_n_input, 3'b000, estado[3:0]};

assign debug = {debug_b3, debug_b2, debug_b1, debug_b0};
/*************************************************************/

endmodule


/////////////////////////////////////////////////
// A PARTIR DAQUI
// Modulos separados que eu fiz
/////////////////////////////////////////////////


// filtro fir
module filtro(
   input clk,
   input reset,
   input enable,
   input [31:0] entrada,
   output reg [31:0] saida
   );

   // numero de coeficientes do filtro
   parameter N = 197;


   parameter [31:0] C [0:N] = { 
     83, -25, -25, -26, -27, -28, -26, -22, -16, -8, 2, 13, 22, 30, 34, 33, 28, 19, 6, -9, -24,
    -38, -47, -52, -50, -41, -26, -6, 16, 38, 57, 70, 75, 70, 55, 32, 3, -29, -60, -85, -101,
    -105, -96, -73, -39, 3, 48, 90, 123, 143, 145, 129, 95, 45, -14, -76, -133, -177, -201,
    -201, -174, -123, -51, 34, 121, 199, 258, 289, 284, 241, 163, 56, -69, -197, -312, -397,
    -439, -427, -357, -232, -59, 143, 355, 549, 699, 778, 765, 644, 408, 62, -383, -902, -1465,
    -2035, -2572, -3037, -3398, -3625, 29065, -3625, -3398, -3037, -2572, -2035, -1465, -902,
    -383, 62, 408, 644, 765, 778, 699, 549, 355, 143, -59, -232, -357, -427, -439, -397, -312,
    -197, -69, 56, 163, 241, 284, 289, 258, 199, 121, 34, -51, -123, -174, -201, -201, -177,
    -133, -76, -14, 45, 95, 129, 145, 143, 123, 90, 48, 3, -39, -73, -96, -105, -101, -85, -60,
    -29, 3, 32, 55, 70, 75, 70, 57, 38, 16, -6, -26, -41, -50, -52, -47, -38, -24, -9, 6, 19,
    28, 33, 34, 30, 22, 13, 2, -8, -16, -22, -26, -28, -27, -26, -25, -25, 83  };

   
   reg [31:0] buff [0:N];

   integer i, k;
   
   // por a entrada no buffer
   // e calcular a saida
   always @(posedge clk) begin
      if (reset) begin

         for ( i=0 ; i<N ; i=i+1 ) begin
            buff[i] <= 0;
         end

         saida <= 0;
      end
      else if (enable) begin

         for ( k=1 ; k<N ; k=k+1 ) begin
            buff[k-1] <= buff[k];
         end

         buff[N-1] <= entrada;
         
         saida <= 
            buff[  0]*C[  0] + buff[  1]*C[  1] + buff[  2]*C[  2] + buff[  3]*C[  3] + buff[  4]*C[  4] +
            buff[  5]*C[  5] + buff[  6]*C[  6] + buff[  7]*C[  7] + buff[  8]*C[  8] + buff[  9]*C[  9] +
            buff[ 10]*C[ 10] + buff[ 11]*C[ 11] + buff[ 12]*C[ 12] + buff[ 13]*C[ 13] + buff[ 14]*C[ 14] +
            buff[ 15]*C[ 15] + buff[ 16]*C[ 16] + buff[ 17]*C[ 17] + buff[ 18]*C[ 18] + buff[ 19]*C[ 19] +
            buff[ 20]*C[ 20] + buff[ 21]*C[ 21] + buff[ 22]*C[ 22] + buff[ 23]*C[ 23] + buff[ 24]*C[ 24] +
            buff[ 25]*C[ 25] + buff[ 26]*C[ 26] + buff[ 27]*C[ 27] + buff[ 28]*C[ 28] + buff[ 29]*C[ 29] +
            buff[ 30]*C[ 30] + buff[ 31]*C[ 31] + buff[ 32]*C[ 32] + buff[ 33]*C[ 33] + buff[ 34]*C[ 34] +
            buff[ 35]*C[ 35] + buff[ 36]*C[ 36] + buff[ 37]*C[ 37] + buff[ 38]*C[ 38] + buff[ 39]*C[ 39] +
            buff[ 40]*C[ 40] + buff[ 41]*C[ 41] + buff[ 42]*C[ 42] + buff[ 43]*C[ 43] + buff[ 44]*C[ 44] +
            buff[ 45]*C[ 45] + buff[ 46]*C[ 46] + buff[ 47]*C[ 47] + buff[ 48]*C[ 48] + buff[ 49]*C[ 49] +
            buff[ 50]*C[ 50] + buff[ 51]*C[ 51] + buff[ 52]*C[ 52] + buff[ 53]*C[ 53] + buff[ 54]*C[ 54] +
            buff[ 55]*C[ 55] + buff[ 56]*C[ 56] + buff[ 57]*C[ 57] + buff[ 58]*C[ 58] + buff[ 59]*C[ 59] +
            buff[ 60]*C[ 60] + buff[ 61]*C[ 61] + buff[ 62]*C[ 62] + buff[ 63]*C[ 63] + buff[ 64]*C[ 64] +
            buff[ 65]*C[ 65] + buff[ 66]*C[ 66] + buff[ 67]*C[ 67] + buff[ 68]*C[ 68] + buff[ 69]*C[ 69] +
            buff[ 70]*C[ 70] + buff[ 71]*C[ 71] + buff[ 72]*C[ 72] + buff[ 73]*C[ 73] + buff[ 74]*C[ 74] +
            buff[ 75]*C[ 75] + buff[ 76]*C[ 76] + buff[ 77]*C[ 77] + buff[ 78]*C[ 78] + buff[ 79]*C[ 79] +
            buff[ 80]*C[ 80] + buff[ 81]*C[ 81] + buff[ 82]*C[ 82] + buff[ 83]*C[ 83] + buff[ 84]*C[ 84] +
            buff[ 85]*C[ 85] + buff[ 86]*C[ 86] + buff[ 87]*C[ 87] + buff[ 88]*C[ 88] + buff[ 89]*C[ 89] +
            buff[ 90]*C[ 90] + buff[ 91]*C[ 91] + buff[ 92]*C[ 92] + buff[ 93]*C[ 93] + buff[ 94]*C[ 94] +
            buff[ 95]*C[ 95] + buff[ 96]*C[ 96] + buff[ 97]*C[ 97] + buff[ 98]*C[ 98] + buff[ 99]*C[ 99] +
            buff[100]*C[100] + buff[101]*C[101] + buff[102]*C[102] + buff[103]*C[103] + buff[104]*C[104] +
            buff[105]*C[105] + buff[106]*C[106] + buff[107]*C[107] + buff[108]*C[108] + buff[109]*C[109] +
            buff[110]*C[110] + buff[111]*C[111] + buff[112]*C[112] + buff[113]*C[113] + buff[114]*C[114] +
            buff[115]*C[115] + buff[116]*C[116] + buff[117]*C[117] + buff[118]*C[118] + buff[119]*C[119] +
            buff[120]*C[120] + buff[121]*C[121] + buff[122]*C[122] + buff[123]*C[123] + buff[124]*C[124] +
            buff[125]*C[125] + buff[126]*C[126] + buff[127]*C[127] + buff[128]*C[128] + buff[129]*C[129] +
            buff[130]*C[130] + buff[131]*C[131] + buff[132]*C[132] + buff[133]*C[133] + buff[134]*C[134] +
            buff[135]*C[135] + buff[136]*C[136] + buff[137]*C[137] + buff[138]*C[138] + buff[139]*C[139] +
            buff[140]*C[140] + buff[141]*C[141] + buff[142]*C[142] + buff[143]*C[143] + buff[144]*C[144] +
            buff[145]*C[145] + buff[146]*C[146] + buff[147]*C[147] + buff[148]*C[148] + buff[149]*C[149] +
            buff[150]*C[150] + buff[151]*C[151] + buff[152]*C[152] + buff[153]*C[153] + buff[154]*C[154] +
            buff[155]*C[155] + buff[156]*C[156] + buff[157]*C[157] + buff[158]*C[158] + buff[159]*C[159] +
            buff[160]*C[160] + buff[161]*C[161] + buff[162]*C[162] + buff[163]*C[163] + buff[164]*C[164] +
            buff[165]*C[165] + buff[166]*C[166] + buff[167]*C[167] + buff[168]*C[168] + buff[169]*C[169] +
            buff[170]*C[170] + buff[171]*C[171] + buff[172]*C[172] + buff[173]*C[173] + buff[174]*C[174] +
            buff[175]*C[175] + buff[176]*C[176] + buff[177]*C[177] + buff[178]*C[178] + buff[179]*C[179] +
            buff[180]*C[180] + buff[181]*C[181] + buff[182]*C[182] + buff[183]*C[183] + buff[184]*C[184] +
            buff[185]*C[185] + buff[186]*C[186] + buff[187]*C[187] + buff[188]*C[188] + buff[189]*C[189] +
            buff[190]*C[190] + buff[191]*C[191] + buff[192]*C[192] + buff[193]*C[193] + buff[194]*C[194] +
            buff[195]*C[195] + buff[196]*C[196];

      end
      
   end

endmodule
