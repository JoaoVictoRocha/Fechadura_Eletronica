module FechaduraTop (
		input 	logic clk,                 // Clock principal de 50MHz da placa
		input 	logic rst,                 // Sinal de reset do botão (ativo alto)
		input 	logic sensor_de_contato, 
		input 	logic botao_interno,
		input		logic [3:0] matricial_col,
		output	logic [3:0] matricial_lin,
		output 	logic [6:0] dispHex0, 
		output 	logic [6:0] dispHex1, 
		output 	logic [6:0] dispHex2, 
		output 	logic [6:0] dispHex3, 
		output 	logic [6:0] dispHex4, 
		output 	logic [6:0] dispHex5,
		output 	logic tranca, 
		output 	logic bip 
		);

	// --- Sinais Internos (Fios de Conexão) ---
	
	// Clock e Reset
	logic clk_1khz;       // Clock de 1KHz para a lógica principal
	logic sys_rst;        // Sinal de reset do sistema, gerado após 5s
	
	// Comunicação com o Teclado
	logic [3:0] key_code;
	logic key_valid;
	
	// Comunicação entre Operacional e Setup
	logic setup_on;
	logic setup_end;
	setupPac_t data_setup_old;
	setupPac_t data_setup_new;
	
	// Comunicação com o Display (sinais dos módulos)
	bcdPac_t bcd_out_op, bcd_out_setup;
	logic bcd_enable_op, bcd_enable_setup;
	
	// Sinais multiplexados para o controlador do display
	bcdPac_t bcd_mux_out;
	logic bcd_mux_enable;
	
	// Sinal interno para inverter a tranca
	logic tranca_inversa;
	assign tranca = ~tranca_inversa;

	// --- Instanciação dos Módulos ---

	// 1. Divisor de Frequência: Gera 1KHz a partir de 50MHz
	divfreq DivisorDeFrequencia (
		.reset(rst), // O reset do divisor é opcional aqui
		.clock(clk), 
		.clk_i(clk_1khz)
	);

	// 2. Lógica de Reset: Gera o reset do sistema (sys_rst) se rst for segurado por 5s
	// Usa o clock de 1KHz para facilitar a contagem
	resetHold5s ResetLogica (
		.clk(clk), 
		.reset_in(rst), 
		.reset_out(sys_rst)
	);

	// 3. Decodificador de Teclado Matricial
	// Usa o clock rápido (50MHz) para varredura e debounce
	matrixKeyDecoder Teclado (
		.clk(clk_1khz), 
		.reset(sys_rst), 
		.col_matrix(matricial_col), 
		.lin_matrix(matricial_lin), 
		.tecla_value(key_code), 
		.tecla_valid(key_valid)
	);

	// 4. Módulo Operacional: Lógica principal da fechadura
	// Usa o clock de 1KHz e o reset do sistema
	operacional Operacional (
		.clk(clk_1khz), 
		.rst(sys_rst), 
		.sensor_de_contato(sensor_de_contato), 
		.botao_interno(botao_interno), 
		.key_valid(key_valid), 
		.key_code(key_code), 
		.bcd_out(bcd_out_op), 
		.bcd_enable(bcd_enable_op), 
		.tranca(tranca_inversa), 
		.bip(bip), 
		.setup_on(setup_on), 
		.setup_end(setup_end), 
		.data_setup_old(data_setup_old), 
		.data_setup_new(data_setup_new)
	);

	// 5. Módulo de Setup: Lógica do modo de configuração
	// Também usa o clock de 1KHz e o reset do sistema
	setup Setup (
		.clk(clk_1khz), 
		.rst(sys_rst), 
		.key_valid(key_valid), 
		.key_code(key_code), 
		.bcd_out(bcd_out_setup), 
		.bcd_enable(bcd_enable_setup), 
		.data_setup_new(data_setup_new), 
		.data_setup_old(data_setup_old), 
		.setup_on(setup_on), 
		.setup_end(setup_end)
	);

	// 6. MUX para os Displays: Seleciona qual módulo (operacional ou setup) controla os displays
	always_comb begin
		if (setup_on) begin
			bcd_mux_out = bcd_out_setup;
			bcd_mux_enable = bcd_enable_setup;
		end else begin
			bcd_mux_out = bcd_out_op;
			bcd_mux_enable = bcd_enable_op;
		end
	end

	// 7. Controlador dos Displays de 7 Segmentos
	// Usa o clock rápido (50MHz) e o reset do sistema
	SixDigit7SegCtrl Displays (
		.clk(clk_1khz), 
		.rst(sys_rst), 
		.enable(bcd_mux_enable), 
		.bcd_packet(bcd_mux_out), 
		.HEX0(dispHex0), 
		.HEX1(dispHex1), 
		.HEX2(dispHex2), 
		.HEX3(dispHex3), 
		.HEX4(dispHex4), 
		.HEX5(dispHex5)
	);
		
endmodule