// Módulo: operacional
// Descrição: Lógica principal de operação da fechadura eletrônica.
// Lógica da Tranca: 0 = Travado, 1 = Destravado

module operacional (
	input 	logic 		clk, 
	input 	logic 		rst, 
	// Lógica do sensor: 1: Aberta, 0: Fechada
	input 	logic 		sensor_de_contato, 
	input 	logic 		botao_interno,
	input 	logic 		key_valid,
	input		logic [3:0] key_code,
	output 	bcdPac_t 	bcd_out,
	output 	logic 		bcd_enable,
	output 	logic		tranca, // 0: Travada, 1: Destravada
	output 	logic 		bip,
	output 	logic 		setup_on,
	input		logic 		setup_end,
	output 	setupPac_t  data_setup_old,
	input 	setupPac_t  data_setup_new
);

	// Estados da FSM
	typedef enum logic [3:0] {
		RESETADO,
		MONTAR_PIN,
		VERIFICAR_SENHA,
		ESPERA,
		SETUP,
		TRAVA_OFF,
		TRAVA_ON,
		PORTA_ABERTA,
		PORTA_FECHADA,
		UPDATE_MASTER,
		FALHA,
		ESPERA_FALHA
	} estado_t;
	 
	estado_t estado, proximo_estado;

	// Sinais de controle
	pinPac_t pin_input, novo_master;
	logic senha_fail, senha_padrao, senha_master, senha_master_update;
	logic fluxo_pos_reset;

	// Sinais para detecção de borda do botão interno
	logic botao_interno_prev;
	logic rising_edge_botao;

	// Contadores
	logic [7:0] cont_falha;
	logic [15:0] cont_espera_falha; 
	logic [6:0] cont_bip, cont_trava;
	
	// Sinais internos
	setupPac_t setup_data;
	logic reset_contadores_porta, reset_cont_falha;
	logic [31:0] tempo_espera_seg;
	
	// Gerador de pulso de 1 segundo (para clk de 1KHz)
	logic [9:0] cont_1s;
	logic one_sec_tick;

	// Sinal para filtrar o key_valid antes de ir para o montar_pin
	logic filtered_key_valid;

	// O teclado só funciona se a porta estiver fechada (sensor==0).
	assign filtered_key_valid = (sensor_de_contato == 1'b0 || key_code > 4'h9) ? key_valid : 1'b0;

	// Lógica combinacional para detectar a borda do botão
	assign rising_edge_botao   = (botao_interno == 1'b1 && botao_interno_prev == 1'b0);

	// Atribuição da saída para o módulo de setup
	assign data_setup_old = setup_data;

	// Instanciações dos submódulos
	montar_pin montar (
		.clk(clk), 
		.rst(rst), 
		.key_valid(filtered_key_valid),
		.key_code(key_code), 
		.pin_out(pin_input)
	);

	verificar_senha verifica (
		.clk(clk), 
		.rst(rst), 
		.pin_in(pin_input), 
		.data_setup(setup_data),
		.senha_fail(senha_fail), 
		.senha_padrao(senha_padrao),
		.senha_master(senha_master), 
		.senha_master_update(senha_master_update)
	);
	
	update_master atualizar (
		.clk(clk), 
		.rst(rst), 
		.enable(estado == UPDATE_MASTER),
		.pin_in(pin_input), 
		.new_master_pin(novo_master)
	);

	// Bloco de estado e atualização de dados (síncrono)
	always_ff @(posedge clk or posedge rst) begin
		if(rst) begin
			estado <= RESETADO;
			fluxo_pos_reset <= 1'b1;
			// Valores padrão do sistema no reset
			setup_data.bip_status <= 1;
			setup_data.bip_time <= 5;
			setup_data.tranca_aut_time <= 5;
			setup_data.master_pin.status <= 1;
			setup_data.master_pin.digit1 <= 4'h1;
			setup_data.master_pin.digit2 <= 4'h2;
			setup_data.master_pin.digit3 <= 4'h3;
			setup_data.master_pin.digit4 <= 4'h4;
			setup_data.pin1.status <= 1;
			setup_data.pin1.digit1 <= 4'h0;
			setup_data.pin1.digit2 <= 4'h0;
			setup_data.pin1.digit3 <= 4'h0;
			setup_data.pin1.digit4 <= 4'h0;
			setup_data.pin2.status <= 0;
			setup_data.pin3.status <= 0;
			setup_data.pin4.status <= 0;
		end else begin
			estado <= proximo_estado;
			
			if (estado == UPDATE_MASTER && novo_master.status && fluxo_pos_reset) begin
				fluxo_pos_reset <= 1'b0;
			end

			if (novo_master.status) begin
				setup_data.master_pin <= novo_master;
			end
			
			if (setup_end) begin
				setup_data <= data_setup_new;
			end
		end
	end

	// Bloco de contadores e registradores (síncrono)
	always_ff @(posedge clk or posedge rst) begin
		if (rst) begin
			cont_falha <= 0;
			cont_bip <= 0;
			cont_trava <= 0;
			cont_espera_falha <= 0;
			cont_1s <= 0;
			one_sec_tick <= 0;
			botao_interno_prev <= 0;
		end else begin
			botao_interno_prev <= botao_interno;

			if (cont_1s == 999) begin
				cont_1s <= 0;
				one_sec_tick <= 1;
			end else begin
				cont_1s <= cont_1s + 1;
				one_sec_tick <= 0;
			end
			
			if (reset_cont_falha) begin
				cont_falha <= 0;
			end else if (estado == VERIFICAR_SENHA && senha_fail) begin
				cont_falha <= cont_falha + 1;
			end

			if (one_sec_tick) begin
				if (estado == ESPERA_FALHA) begin
					if(cont_espera_falha < tempo_espera_seg)
						cont_espera_falha <= cont_espera_falha + 1;
				end else begin
					cont_espera_falha <= 0;
				end
				
				if (estado == PORTA_ABERTA && sensor_de_contato) begin 
					cont_trava <= 0;
					if (cont_bip < setup_data.bip_time)
						cont_bip <= cont_bip + 1;
				end
				
				if (estado == PORTA_FECHADA && !sensor_de_contato) begin
					cont_bip <= 0;
					if (cont_trava < setup_data.tranca_aut_time)
						cont_trava <= cont_trava + 1;
				end
			end
			
			if(reset_contadores_porta) begin
				cont_bip <= 0;
				cont_trava <= 0;
			end
		end
	end

	// Bloco de lógica combinacional (próximo estado e saídas)
	always_comb begin
		proximo_estado = estado;
		
		// Saídas padrão
		tranca = 1'b0; // ALTERAÇÃO: Padrão é travado (0)
		bip = 0;
		bcd_enable = 0;
		bcd_out = '{default:4'hA};
		setup_on = 0;
		reset_contadores_porta = 0;
		reset_cont_falha = 0;
		
		// Lógica para tempo de espera por falhas
		if (cont_falha < 3)      tempo_espera_seg = 1;
		else if (cont_falha == 3) tempo_espera_seg = 10;
		else if (cont_falha == 4) tempo_espera_seg = 20;
		else                      tempo_espera_seg = 30;
		
		// Máquina de Estados Principal
		case (estado) 
			RESETADO: begin
				tranca = 1'b1; // Começa destravada se a porta estiver aberta
				if (!sensor_de_contato) begin
					proximo_estado = MONTAR_PIN;
				end
			end
			
			ESPERA: begin
				proximo_estado = TRAVA_ON;
			end
			
			MONTAR_PIN: begin
				bcd_enable = 1;
				bcd_out.BCD0 = pin_input.digit4;
				bcd_out.BCD1 = pin_input.digit3;
				bcd_out.BCD2 = pin_input.digit2;
				bcd_out.BCD3 = pin_input.digit1;

				if (pin_input.status) begin
					proximo_estado = VERIFICAR_SENHA;
				end else if (rising_edge_botao && fluxo_pos_reset) begin
					proximo_estado = TRAVA_OFF;
				end
			end
			
			VERIFICAR_SENHA: begin
				if (senha_fail) begin
					proximo_estado = FALHA;
				end else if (senha_padrao) begin
					reset_cont_falha = 1; 
					proximo_estado = TRAVA_OFF;
				end else if (senha_master) begin
					reset_cont_falha = 1;
					proximo_estado = UPDATE_MASTER;
				end
			end
			
			FALHA: begin
				bcd_enable = 1;
				bcd_out = '{default:4'hB};
				proximo_estado = ESPERA_FALHA;
			end

			ESPERA_FALHA: begin
				bcd_enable = 1;
				bcd_out = '{default:4'hB};
				if (cont_espera_falha >= tempo_espera_seg)
					proximo_estado = TRAVA_ON;
			end
			
			TRAVA_OFF: begin 
				tranca = 1'b1; // ALTERAÇÃO: DESTRAVADO
				reset_contadores_porta = 1;
				proximo_estado = PORTA_ABERTA;
			end
			
			PORTA_ABERTA: begin 
				tranca = 1'b1; // ALTERAÇÃO: DESTRAVADO
				if (!sensor_de_contato) begin
					reset_contadores_porta = 1;
					proximo_estado = PORTA_FECHADA;
				end else if (cont_bip >= setup_data.bip_time && setup_data.bip_status) begin
					bip = 1; 
				end
			end
			
			PORTA_FECHADA: begin 
				tranca = 1'b1; // ALTERAÇÃO: DESTRAVADO
				if (sensor_de_contato) begin
					reset_contadores_porta = 1;
					proximo_estado = PORTA_ABERTA;
				end else if (rising_edge_botao) begin
					proximo_estado = TRAVA_ON; 
				end else if (cont_trava >= setup_data.tranca_aut_time) begin
					proximo_estado = TRAVA_ON; 
				end
			end
			
			TRAVA_ON: begin 
				tranca = 1'b0; // ALTERAÇÃO: TRAVADO
				bip = 0;
				proximo_estado = TRAVA_ON;

				bcd_enable = 1;
				bcd_out = '{default:4'hA};

				if (filtered_key_valid) begin 
					proximo_estado = MONTAR_PIN;
				end else if (rising_edge_botao) begin 
					proximo_estado = TRAVA_OFF;
				end
			end
			
			UPDATE_MASTER: begin
				bcd_enable = 1;
				bcd_out.BCD5 = 4'hA;
				bcd_out.BCD4 = 4'hE;
				
				bcd_out.BCD3 = pin_input.digit1;
				bcd_out.BCD2 = pin_input.digit2;
				bcd_out.BCD1 = pin_input.digit3;
				bcd_out.BCD0 = pin_input.digit4;

				if (novo_master.status) begin
					if (fluxo_pos_reset) begin
						proximo_estado = TRAVA_ON;
					end else begin
						proximo_estado = SETUP;
					end
				end
			end
			
			SETUP: begin
				setup_on = 1; 
				if (setup_end)
					proximo_estado = TRAVA_ON;
			end
			
			default: proximo_estado = RESETADO;

		endcase
	end
endmodule