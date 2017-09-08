/*
  Filename:    reg128_pl.v
  Author:      Moein Pahlavan Yali
  Date:        10-31-2013
  Version:     1
  Website:		http://rijndael.ece.vt.edu/de2i150/
  Description: Custom logic for driving AES module. Integrated in QSYS to be used on DE2i-150 board as AES co-processor
*/
module custom_logic_top(
	clk_input,
   rst_n_input,
	master_clk,
   master_rst_n,
   master_address,
   master_readdata,
   master_writedata,
   master_read,
   master_write,
   master_waitrequest,
   master_byteen,
	status_port,
   command_port,
   switch_entrada_input,
	debug
);

input clk_input, rst_n_input;
output master_clk, master_rst_n;
input master_waitrequest;
output master_write, master_read;
input [31:0] master_readdata, command_port;
output reg [31:0] master_writedata;
output [31:0] debug, status_port;
output [9:0] master_address;
output [3:0] master_byteen;

input [17:0] switch_entrada_input;


// trocando por um clock de 1 hz pra eu poder ver os leds de debug
/*clock1hz clk1hz0 ( .clk50mhz_in(clk_input),
                   .rst_in(~rst_n_input),
                   .clk_out(clk) ); */

wire rst_n, clk;
assign clk = clk_input; // troquei por clock de 1 hz pra ver os leds de debug
assign rst_n = rst_n_input;


// for Avalon MM Master Interface
wire [31:0] master_readdata_translate; // Big Endian <=> Little Endian
reg master_write_r;
reg [7:0] master_writedata_r;
reg [9:0] master_address_r;

assign master_clk = clk_input;
assign master_rst_n = rst_n_input;
assign master_address = master_address_r;
assign master_write = master_write_r;
assign master_byteen = 4'b1111;
assign master_readdata_translate = {master_readdata[7:0], master_readdata[15:8], master_readdata[23:16], master_readdata[31:24]};


always@(posedge clk) begin
  //master_writedata <= 32'h00000007;
  //master_writedata <= { 14'd0, switch_entrada_input};
  master_writedata <= out_da_ram2;
end

// for State Machine (Controller)
parameter AGUARDANDO = 4'd0,
          LEITURA_INICIAR = 4'd1,
          LEITURA_LOOP = 4'd2,
          OPERACAO_INICIAR = 4'd5,
          OPERACAO_ESPERAR = 4'd6,
          ESCRITA_RESULTADO = 4'd7,
          CONCLUIDO = 4'd8;

wire req, aes_done;
wire [127:0] plaintext, key, ciphertext;
reg carregar_dados, plaintext_load, ciphertext_load, fire_calculo, req_r, ack_r, busy;
reg [3:0] state;
reg [4:0] cnt;
reg [1:0] key_segment, plaintext_segment, write_segment;

// status and command port assignments
assign status_port = {31'd0, ack_r};
assign req = command_port[0];

reg calcula_samples;

reg [2:0] tem_fogo;

// Controller
always@(posedge clk) begin
	master_write_r <= 0;
	master_address_r <= 0;
	carregar_dados <= 0;
	plaintext_load <= 0;
	ciphertext_load <= 0;
	key_segment <= 0;
	plaintext_segment <= 0;
	write_segment <= 0;
	fire_calculo <= 0;
	ack_r <= 0;
   
   calcula_samples <= 0;
   
	if(~rst_n) begin		// Reset	
		state <= AGUARDANDO;
		busy <= 0;
	end
	else begin
		case(state)
			AGUARDANDO: begin	
					if(req) begin	// Start
						state <= LEITURA_INICIAR;
						busy <= 1;
					end
					else state <= 0;	// 
				end
			LEITURA_INICIAR:	// 
				begin
					master_write_r <= 0;
					master_address_r <= 0;
					cnt <= 1;
					state <= LEITURA_LOOP;
				end
			LEITURA_LOOP:	// 
				begin
					master_write_r <= 0;
					carregar_dados <= 1;
					key_segment <= 4-cnt;
					master_address_r <= cnt*4;
					cnt <= cnt+1;
					if(cnt == 4) state <= OPERACAO_INICIAR;
					else state <= LEITURA_LOOP;
				end
			OPERACAO_INICIAR:	//  (pulse on fire_calculo)
				begin
					fire_calculo <= 1;
               tem_fogo = 3'b111;
					state <= OPERACAO_ESPERAR;
               cnt <= 1;
				end
			OPERACAO_ESPERAR:	
				begin
					//if(aes_done) begin
               if(cnt == 4) begin
                  cnt <= 0;
						state <= ESCRITA_RESULTADO;
					end
					else begin
                  state <= OPERACAO_ESPERAR;
						cnt <= cnt+1;
                  calcula_samples <= 1;
               end
				end
			ESCRITA_RESULTADO:	
				begin
					master_write_r <= 1;
					key_segment <= 3-cnt;
					master_address_r <= 32+cnt*4;
					cnt <= cnt+1;
					if(cnt == 3) state <= CONCLUIDO;
					else state <= ESCRITA_RESULTADO;
				end
			CONCLUIDO:
				begin
					ack_r <= 1;
					busy <= 0;
					if(~req) state <= AGUARDANDO;
					else state <= CONCLUIDO;
				end
			default: state <= AGUARDANDO;
		endcase
	end
   
end
   
wire [31:0] negativ_out;
   
negativador ng0 ( .clk(clk),
                  .reset(fire_calculo),
                  .entrada(out_da_ram),
                  .saida(negativ_out) );

parameter NULL = 32'b00000000000000000000000000000000;

wire ram_write_enable;
wire [31:0] ram_addr_read_in;
wire [31:0] ram_addr_wrte_in;
wire [31:0] ram_data_in;
wire [31:0] out_da_ram;
wire [31:0] out_da_ram2;

assign ram_write_enable = carregar_dados | calcula_samples;
assign ram_addr_read_in = { 27'b000000000000000000000000000, cnt };
assign ram_addr_wrte_in = (state==OPERACAO_ESPERAR) ?
                          ( 32'h00000008 + { 27'b000000000000000000000000000, cnt } ) :
                          { 30'b000000000000000000000000000000, key_segment } ;
assign ram_data_in = (state==OPERACAO_ESPERAR) ?
                     negativ_out :
                     master_readdata /*master_readdata_translate*/ ;

/*
ram ram0( .clk(clk),
          .write_enable( ram_write_enable ),
          .addr_read_in( ram_addr_read_in ),
          .addr_wrte_in( ram_addr_wrte_in ),
          .data_in( ram_data_in ),
          .data_out(out_da_ram) );
*/

//////////////////////////////////////////////////////////////////////////////////////////////////////////////////////q
//////////////////////////////////////////////////////////////////////////////////////////////////////////////////////q
//////////////////////////////////////////////////////////////////////////////////////////////////////////////////////q

ram ram0( .clk(clk),
          .write_enable( carregar_dados ),
          .addr_read_in( { 27'b000000000000000000000000000, cnt } ),
          .addr_wrte_in( { 27'b000000000000000000000000000, cnt } ),
          .data_in( master_readdata ),
          .data_out(out_da_ram) );
          
ram ram1( .clk(clk),
          .write_enable( calcula_samples ),
          .addr_read_in( { 27'b000000000000000000000000000, (cnt + 5'd1) } ),
          .addr_wrte_in( { 27'b000000000000000000000000000, cnt } ),
          .data_in( negativ_out ),
          .data_out(out_da_ram2) );

//////////////////////////////////////////////////////////////////////////////////////////////////////////////////////q
//////////////////////////////////////////////////////////////////////////////////////////////////////////////////////q
//////////////////////////////////////////////////////////////////////////////////////////////////////////////////////q


/*************************************************************/
// Debug Data
wire [7:0] debug_b3, debug_b2, debug_b1, debug_b0;
assign debug_b0 = plaintext[7:0];
assign debug_b1 = key[7:0];
assign debug_b2 = 8'hff;
//assign debug_b3 = {rst_n_input, 3'b000, state[3:0]};
assign debug_b3 = {rst_n_input, tem_fogo, state[3:0]};

assign debug = {debug_b3, debug_b2, debug_b1, debug_b0};

endmodule



/////////////////////////////////////////////////
//
// A PARTIR DAQUI
//
// Modulos separados que eu fiz ou pra teste
// ou direcionados para a aplicacao fina que
// vou tentar apresentar (a de convolucao).
/////////////////////////////////////////////////



module negativador (
   input wire clk,
   input wire reset,
   input wire [31:0] entrada,
   output reg [31:0] saida
   );
   
   always @(posedge clk) begin
      if (reset) begin
         saida <= 0;
      end else begin         
         saida <= (entrada); // FAZENDO NADA
      end
   end
   
endmodule

///////////////////////////////////////////////////////////////////////////////
// RAM (mimics) (Tiago)
///////////////////////////////////////////////////////////////////////////////
module ram(
   input wire clk,
   input wire write_enable,
   input wire [31:0] addr_read_in,
   input wire [31:0] addr_wrte_in,
   input wire [31:0] data_in,
   output reg [31:0] data_out
   );

   reg [31:0] mem [0:2047];
   //reg [31:0] mem [0:131071]; // 512 kb (da numa CycloneIV)

   // random stuff
   //initial
   //begin
   //   $readmemh("valores_memoria.dat", mem);
   //end

   always @(posedge clk) begin
      if (write_enable) mem[addr_wrte_in] <= data_in;
   end

   always @(posedge clk) begin
      data_out <= mem[addr_read_in];
   end
   
endmodule



module filtro(clk, reset);

   // CONSTANTES
   parameter N = 3;
   parameter samples = 20;
   parameter NULL = 32'b00000000000000000000000000000000;
   
   // ENTRADAS
   input clk;
   input reset;
   
   // REGS
   reg [31:0] k;
   
   // WIRES
   //wire [31:0] w_;
   
   // INITIALS
   //initial count = 0;
   
   always @(posedge clk) begin
      if (reset) begin
         k <= 0;
      end else begin         
         if (k < samples) begin            
            k <= k + 1;
         end else
         begin            
            k <= 0;
         end
      end
   end
   
   reg [31:0] a1;
   reg [31:0] a2;
   reg [31:0] a3;
   
   always @(posedge clk) begin
      if (reset) begin
         a1 <= 0;
         a2 <= 0;
         a3 <= 0;
      end else begin
         a1 = a2;
         a2 = a3;
         a3 = out;
         
         in <= 1*a1 + 2*a2 + 1*a3; // aqui, coefs da resp. a impulso
      end
   end
   
   wire we;
   wire [31:0] addr;
   reg [31:0] in;
   wire [31:0] out;
   
   ram ram1 ( .clk(clk),
              .write_enable(0), 
              .addr_read_in(k),
              .addr_wrte_in(NULL),
              .data_in(NULL),
              .data_out(out) );

endmodule


// converte o clock de 50MHz pra 1Hz
module clock1hz(
   input wire clk50mhz_in, // de 50 MHz
   input wire rst_in,
   output reg clk_out
   );

   reg [31:0] cnt;

   initial begin
      cnt = 0;
      clk_out = 0;
   end

   always @(negedge clk50mhz_in) begin
      if(rst_in) begin
         cnt <= 0;
         clk_out <= 0;
      end
      else begin
         if (cnt == 12500000) begin
            clk_out <= ~clk_out;
            cnt <= 0;
         end
         else begin
            cnt <= cnt + 1;
         end
      end
   end

endmodule
