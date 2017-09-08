
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

// offsets para as posicoes dos dados de
// entrada e saida na memoria interna
parameter OFFSET_ENTRADA = 0,
          OFFSET_SAIDA = 512;

// Estados da FSM (codificados em one-hot)
parameter ESPERANDO  = 4'b0001,
          CARREGANDO = 4'b0010,
          CALCULANDO = 4'b0100,
          PRONTO     = 4'b1000;

// NUMERO DE AMOSTRAS (int32) DO BLOCO DE DADOS
parameter SIZE = 16'd128;

reg [3:0] estado;
reg [15:0] posicao;

reg cmd_executar;

reg enable_calcular;
reg reset_filtro;

reg resetn_interno_reg;

reg [31:0] mem [0:2047];

reg [31:0] filtro_in;

//reg [31:0] correcao;

// controlador baseado em FSM
always@(posedge clk) begin

   //correcao <= {14'd0, switch_entrada_input};
   cmd_executar <= command_port[0];

   if(~rst_n) begin  // reset
      estado <= ESPERANDO;
      resetn_interno_reg <= 1;
      filtro_in <= 32'd0;
      enable_calcular <= 0;
   end
   else begin
      case(estado)
         ESPERANDO:
            begin 
               if(cmd_executar) begin
                  estado <= CARREGANDO;
                  master_write <= 0;
                  master_read <= 1;
                  master_address <= OFFSET_ENTRADA;
                  posicao <= 0;
                  status_port <= 0;
                  reset_filtro <= 1;
               end
               else begin
                  estado <= ESPERANDO;
                  master_write <= 0;
                  master_read <= 0;
                  enable_calcular <= 0;
                  reset_filtro <= 0;
               end
            end
         CARREGANDO:
            begin                              
               reset_filtro <= 0;

               mem[posicao] <= master_readdata;

               if( posicao == (SIZE-1) ) begin
                  estado <= CALCULANDO;
                  posicao <= 0;
                  enable_calcular <= 1;
                  filtro_in <= mem[0]; // necessario, filtro tem atraso de 1 pulso
                  master_write <= 0;
                  master_read <= 0;
                  master_address <= 0;
                  master_writedata <= 0;
               end
               else begin
                  estado <= CARREGANDO;
                  master_write <= 0;
                  master_read <= 1;
                  master_address <= (OFFSET_ENTRADA + posicao*4 + 4);
                  posicao <= posicao+1;
               end
            end
         CALCULANDO:
            begin
               if( posicao == (SIZE-1) ) begin
                  estado <= PRONTO;
                  master_write <= 1;
                  master_read <= 0;
                  master_address <= (OFFSET_SAIDA + posicao*4);
                  master_writedata <= filtro_out;
                  posicao <= posicao+1;
                  enable_calcular <= 0;
                  filtro_in <= 0;
               end
               else begin
                  estado <= CALCULANDO;
                  master_write <= 1;
                  master_read <= 0;
                  master_address <= (OFFSET_SAIDA + posicao*4);
                  master_writedata <= filtro_out; // ja ha valor no 1o pulso do estado
                  posicao <= posicao+1;
                  enable_calcular <= 1;
                  filtro_in <= mem[posicao+1];
               end
            end
         PRONTO:
            begin
               status_port <= 32'd1; // indica conclusao ao processo
               resetn_interno_reg <= 0; // necessario para destravar o app

               master_write <= 0;
               master_read <= 0;
               master_address <= 0;
               master_writedata <= 0;
               posicao <= 0;
               enable_calcular <= 0;
               filtro_in <= 0;

               if(~cmd_executar) begin
                  estado <= ESPERANDO;
               end
               else begin
                  estado <= PRONTO;
               end
            end
         default:
            estado <= ESPERANDO;
      endcase
   end
end

wire [31:0] filtro_out;

filtro f0 ( .clk(clk),
            .reset( ~rst_n_input | reset_filtro ),
            .enable(enable_calcular),
            .entrada( filtro_in ),
            .saida( filtro_out ) //,
            //.correcao( correcao )
          );

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
   output reg [31:0] saida //,
   //input [31:0] correcao
   );

   // numero de coeficientes do filtro
   parameter N = 13;

   // coeficientes do filtro (literal de 32 bits em decimal é padrão no verilog)
   parameter
      C0  = -24738871,
      C1  = -112681234,
      C2  = -170991139,
      C3  = -74200673,
      C4  = 241328526,
      C5  = 620061218,
      C6  = 792031499,
      C7  = 620061218,
      C8  = 241328526,
      C9  = -74200673,
      C10 = -170991139,
      C11 = -112681234,
      C12 = -24738871;
   
   reg [31:0] buff [0:N-1];
   
   wire [63:0] p0, p1, p2, p3, p4, p5;
   wire [63:0] p0p1, p2p3, p4p5;
   wire [63:0] soma;
   
   assign p0 = buff[0]*C0 + buff[1]*C1;
   assign p1 = buff[2]*C2 + buff[3]*C3;
   assign p2 = buff[4]*C4 + buff[5]*C5;
   assign p3 = buff[6]*C6 + buff[7]*C7;
   assign p4 = buff[8]*C8 + buff[9]*C9;
   assign p5 = buff[10]*C10 + buff[11]*C11 + buff[12]*C12;
   
   assign p0p1 = p0 + p1;
   assign p2p3 = p2 + p3;
   assign p4p5 = p4 + p5;
   
   assign soma = p0p1 + p2p3 + p4p5 + 64'h0000_0000_8000_0000;

   integer i, k;
   
   // por a entrada no buffer
   // e atualizar a saida
   always @(posedge clk or posedge reset) begin
      if (reset) begin

         for ( i=0 ; i<N ; i=i+1 ) begin
            buff[i] <= 32'd0;
         end
         
         saida <= 32'd0;
      end
      else if (enable) begin

         for ( k=1 ; k<N ; k=k+1 ) begin
            buff[k-1] <= buff[k];
         end
         
         buff[N-1] <= entrada;
         
         saida = soma[63:32];
      end
      
   end

endmodule

module registrador(
   input clk,
   input reset,
   input [31:0] in,
   output [31:0] out
   );
   
   reg  [31:0] valor;
   
   assign out = valor;

   always @(posedge clk or posedge reset) begin
      if(reset) begin
         valor <= 32'd0;
      end
      else begin
         valor <= in;
      end
   end
   
endmodule
