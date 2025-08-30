/*
pinPacked_t

Tipo de dado usado para empacotar as informações do pin, 
ou seja seu valor e se o mesmo se encontra ativo, inativo e seu valor.
*/


typedef struct packed {
	logic 		status;
	logic [3:0] digit1;
	logic [3:0] digit2;
	logic [3:0] digit3;
	logic [3:0] digit4;
} pinPac_t;


/*
setupPac_t

Tipo de dado usado para empacotar as informações 
transmitidas entre o módulo de setup e o modulo operacional.

*/
typedef struct packed {
	logic 		bip_status;
	logic [6:0] bip_time;
	logic [6:0] tranca_aut_time;
	pinPac_t 	master_pin;
	pinPac_t 	pin1;
	pinPac_t 	pin2;
	pinPac_t 	pin3;
	pinPac_t 	pin4;
	
} setupPac_t;



/*
bcdPacked_t

Tipo de dado usado para empacotar os valores dos displays no formato BCD.
*/
typedef struct packed {
	logic [3:0] BCD0;
	logic [3:0] BCD1;
	logic [3:0] BCD2;
	logic [3:0] BCD3;
	logic [3:0] BCD4;
	logic [3:0] BCD5;
} bcdPac_t;




module divfreq(input reset, clock, output logic clk_i);

  int cont;

  always @(posedge clock or posedge reset) begin
    if(reset) begin
      cont  = 0;
      clk_i = 0;
    end
    else
      if( cont <= 25000 )
        cont++;
      else begin
        clk_i = ~clk_i;
        cont = 0;
      end
  end
endmodule



module BCDto7SEGMENT( input logic[3:0] bcd, output logic [6:0] Seg );

always begin
	 case(bcd) 
		   4'b0000 : Seg = 7'b1000000;
			4'b0001 : Seg = 7'b1111001;
			4'b0010 : Seg = 7'b0100100;
			4'b0011 : Seg = 7'b0110000;
			4'b0100 : Seg = 7'b0011001;
			4'b0101 : Seg = 7'b0010010;
			4'b0110 : Seg = 7'b0000010;
			4'b0111 : Seg = 7'b1111000;
			4'b1000 : Seg = 7'b0000000;
			4'b1001 : Seg = 7'b0011000; 
			4'b1011 : Seg = 7'b0111111;
		default: begin
         Seg = 7'b1111111; // Display apagado
		end
	 endcase
 end
endmodule

// Módulo montar_pin
module montar_pin (
    input  logic      clk,
    input  logic      rst,
    input  logic      key_valid,
    input  logic [3:0] key_code,
    output pinPac_t   pin_out
);
    typedef enum logic [2:0] {
        INICIAL,
        DIGITO_LIDO,
        STATUS_TRUE,
        HOLD_STATUS,
        TEMP
    } estado_t;
    estado_t ESTADO_ATUAL;
	 logic key_valid_prev;
	 logic has_blank_digit;
	 
	 assign has_blank_digit = (pin_out.digit1 == 4'hE) || (pin_out.digit2 == 4'hE) ||
                                          (pin_out.digit3 == 4'hE) || (pin_out.digit4 == 4'hE);


    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            ESTADO_ATUAL <= INICIAL;
            key_valid_prev <= 0;
            pin_out <= '{status: 0, digit1: 4'hE, digit2: 4'hE, digit3: 4'hE, digit4: 4'hE};
        end else begin
				key_valid_prev <= key_valid;
            case (ESTADO_ATUAL)
                INICIAL: begin
                    pin_out.status <= 0;
                    if (key_valid && !key_valid_prev && key_code <= 4'h9) begin
                        ESTADO_ATUAL <= DIGITO_LIDO;
                        pin_out.digit1 <= pin_out.digit2;
                        pin_out.digit2 <= pin_out.digit3;
                        pin_out.digit3 <= pin_out.digit4;
                        pin_out.digit4 <= key_code;
                    end
                end
							
                DIGITO_LIDO: begin
                    if (key_valid && !key_valid_prev && key_code == 4'hF && !has_blank_digit) begin
                        ESTADO_ATUAL <= STATUS_TRUE;
                    
                    end else if (key_valid && !key_valid_prev && key_code <= 4'h9) begin
                        pin_out.digit1 <= pin_out.digit2;
                        pin_out.digit2 <= pin_out.digit3;
                        pin_out.digit3 <= pin_out.digit4;
                        pin_out.digit4 <= key_code;
                    end
                end

                STATUS_TRUE: begin
                    pin_out.status <= 1;
                    ESTADO_ATUAL <= HOLD_STATUS;
                end

                HOLD_STATUS: begin
                    pin_out.status <= 1;
                    ESTADO_ATUAL <= TEMP;
                end

                TEMP: begin
                    if (pin_out.status) begin
                        pin_out.status <= 0;
                    end else begin
                      pin_out <= '{status: 0, digit1: 4'hE, digit2: 4'hE, digit3: 4'hE, digit4: 4'hE};
                      ESTADO_ATUAL <= INICIAL;
                    end
                end
            endcase
        end
    end
endmodule

// Modulo verificar senha
module verificar_senha (
    input  logic       clk,
    input  logic       rst,
    input  pinPac_t    pin_in,
    input  setupPac_t  data_setup,
    output logic       senha_fail,
    output logic       senha_padrao,
    output logic       senha_master,
    output logic       senha_master_update
);

    typedef enum logic [3:0] {
        RESETADO,
        ESPERA,
        VERIFICAR,
        CHECK_PIN,
        MASTER_UPDATE,
        MASTER_OK,
        MASTER_VALID,
        FAIL_FLAG,
        SETUP_FLAG,
        PIN_FLAG,
        UPDATE_FLAG,
        PIN_VALID,
        HOLD_FLAGS,
        TEMP
    } state_t;

    state_t     estado;
    state_t     estado_ant;
    logic       status_d;
    pinPac_t    pin_temp;

    // Armazena status do ciclo anterior
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            status_d <= 0;
				
        end else begin
            status_d <= pin_in.status;
        end
    end

    // Estado principal
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            estado <= RESETADO;
        end else begin
            case (estado)
                RESETADO: begin
                    estado <= ESPERA;
                end

                ESPERA: begin
                    if (pin_in.status && !status_d) begin
                        estado <= VERIFICAR;
                        pin_temp <= pin_in;
                        pin_temp.status <= 1;
                    end
                end

                VERIFICAR: begin
                    if (senha_master_update) begin
                        estado <= MASTER_UPDATE;
                    end else begin
                        estado <= CHECK_PIN;
                    end
                end

                CHECK_PIN: begin
                    if (pin_temp.digit1 == data_setup.master_pin.digit1 &&
                        pin_temp.digit2 == data_setup.master_pin.digit2 &&
                        pin_temp.digit3 == data_setup.master_pin.digit3 &&
                        pin_temp.digit4 == data_setup.master_pin.digit4) begin
                        estado <= MASTER_VALID;

                    end else if (pin_temp.digit1 == data_setup.pin1.digit1 &&
                                 pin_temp.digit2 == data_setup.pin1.digit2 &&
                                 pin_temp.digit3 == data_setup.pin1.digit3 &&
                                 pin_temp.digit4 == data_setup.pin1.digit4
											) begin
                        estado <= PIN_VALID;

                    end else if (pin_temp.digit1 == data_setup.pin2.digit1 &&
                                 pin_temp.digit2 == data_setup.pin2.digit2 &&
                                 pin_temp.digit3 == data_setup.pin2.digit3 &&
                                 pin_temp.digit4 == data_setup.pin2.digit4 &&
                                 data_setup.pin2.status) begin
                        estado <= PIN_VALID;

                    end else if (pin_temp.digit1 == data_setup.pin3.digit1 &&
                                 pin_temp.digit2 == data_setup.pin3.digit2 &&
                                 pin_temp.digit3 == data_setup.pin3.digit3 &&
                                 pin_temp.digit4 == data_setup.pin3.digit4 &&
                                 data_setup.pin3.status) begin
                        estado <= PIN_VALID;

                    end else if (pin_temp.digit1 == data_setup.pin4.digit1 &&
                                 pin_temp.digit2 == data_setup.pin4.digit2 &&
                                 pin_temp.digit3 == data_setup.pin4.digit3 &&
                                 pin_temp.digit4 == data_setup.pin4.digit4 &&
                                 data_setup.pin4.status) begin
                        estado <= PIN_VALID;

                    end else begin
                        estado <= FAIL_FLAG;
                    end
                end

                MASTER_UPDATE: begin
                    if (pin_temp.digit1 == 4'b0001 &&
                        pin_temp.digit2 == 4'b0010 &&
                        pin_temp.digit3 == 4'b0011 &&
                        pin_temp.digit4 == 4'b0100) begin
                        estado <= MASTER_OK;
                    end else begin
                        //senha_fail <= 1;  // Cuidado: sobrescrito abaixo, pode remover
                        estado <= CHECK_PIN;
                    end
                end

                MASTER_OK: begin
                    if (senha_master_update) begin
                        estado <= UPDATE_FLAG;
                    end
                end

                MASTER_VALID: begin
                    if (senha_master) begin
                        estado <= SETUP_FLAG;
                    end
                end

                UPDATE_FLAG: begin
                    if (data_setup.master_pin.status) begin
                        estado <= TEMP;
                    end
                end

                PIN_VALID: begin
                    estado <= PIN_FLAG;
                end

                FAIL_FLAG,
                SETUP_FLAG,
                PIN_FLAG: begin
                    estado <= HOLD_FLAGS;
                end

                HOLD_FLAGS: begin
                    estado <= TEMP;
                end

                TEMP: begin
                    if (!senha_fail && !senha_master && !senha_padrao) begin
                        estado <= ESPERA;
                        pin_temp <= '{status: 0, digit1: 4'b1110, digit2: 4'b1110, digit3: 4'b1110, digit4: 4'b1110};
                    end
                end

                default: estado <= ESPERA;
            endcase
        end
    end

    // Armazena estado anterior
    always_ff @(posedge clk or posedge rst) begin
        if (rst)
            estado_ant <= RESETADO;
        else
            estado_ant <= estado;
    end

    // Sinais de saída (antes combinacionais, agora sincronizados)
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            senha_fail <= 0;
            senha_padrao <= 0;
            senha_master <= 0;
            senha_master_update <= 1;
        end else begin
            // valores default
            senha_fail <= 0;
            senha_padrao <= 0;
            senha_master <= 0;

            case (estado)
                FAIL_FLAG: senha_fail <= 1;
                PIN_FLAG:  senha_padrao <= 1;
                MASTER_VALID,
                UPDATE_FLAG: senha_master <= 1;
                default: ; // já estão zerados
            endcase

            // senha_master_update deve ir para 0 quando sai do TEMP
            if (estado_ant == MASTER_OK) begin
                senha_master_update <= 0;
            end
        end
    end
endmodule

// Módulo update_master
module update_master (
    input  logic      clk,
    input  logic      rst,
    input  logic      enable,
    input  pinPac_t   pin_in,
    output pinPac_t   new_master_pin
);
    typedef enum logic [1:0] {
        INICIAL,
        ATUALIZAR,
        TEMP,
        FINAL
    } estado_t;

    estado_t ESTADO_ATUAL;

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            ESTADO_ATUAL <= INICIAL;
            new_master_pin <= '{status: 0, digit1: 4'b0, digit2: 4'b0, digit3: 4'b0, digit4: 4'b0};
        end else begin
            case (ESTADO_ATUAL)
                INICIAL: begin
                    if (enable) begin
                        ESTADO_ATUAL <= ATUALIZAR;
                    end
                end

                ATUALIZAR: begin
                    if (pin_in.status) begin
								new_master_pin <= pin_in;
							   new_master_pin.status <= 1;
							   ESTADO_ATUAL <= TEMP;
								
                        //new_master_pin <= pin_in;
                        //if (new_master_pin.digit1 == pin_in.digit1 &&
                         //   new_master_pin.digit2 == pin_in.digit2 &&
                          //  new_master_pin.digit3 == pin_in.digit3 &&
                          //  new_master_pin.digit4 == pin_in.digit4) begin
                          //  new_master_pin.status <= 1;
                          //  ESTADO_ATUAL <= TEMP;
                        //end
                    end
                end

                TEMP: begin
                    if (!enable) begin
                        ESTADO_ATUAL <= FINAL;
                    end
                end
	
                FINAL: begin
                    // Estado final, mantém valores
                end
            endcase
        end
    end
endmodule

module matrixKeyDecoder (
    input clk, reset,
    input logic [3:0] col_matrix, // Leitura das colunas
    output logic [3:0] lin_matrix, // Ativação das linhas
    output logic [3:0] tecla_value,
    output logic tecla_valid
);
    localparam DEBOUNCE_TIME = 25; 

    typedef enum {IDLE, SET_ROW, WAIT_STABILIZE, READ_COLS, DEBOUNCE, HOLD_KEY} state_t;
    state_t state;
    
    logic [3:0] lin_reg;
    logic [3:0] key_code_reg;
    logic [1:0] row_scan_counter;
    logic [31:0] debounce_counter;

    assign lin_matrix = lin_reg;
    assign tecla_value = key_code_reg;

    always_ff @(posedge clk or posedge reset) begin
        if (reset) begin
            state <= IDLE;
            row_scan_counter <= 0;
            debounce_counter <= 0;
            tecla_valid <= 0;
            lin_reg <= 4'b1111;
            key_code_reg <= 4'hA;
        end else begin
            tecla_valid <= 0;

            case(state)
                IDLE: begin
                    row_scan_counter <= 0;
                    state <= SET_ROW;
                end

                SET_ROW: begin
                    case(row_scan_counter)
                        2'b00: lin_reg <= 4'b1110; 2'b01: lin_reg <= 4'b1101;
                        2'b10: lin_reg <= 4'b1011; 2'b11: lin_reg <= 4'b0111;
                    endcase
                    state <= WAIT_STABILIZE;
                end

                WAIT_STABILIZE: state <= READ_COLS;

                READ_COLS: begin
                    if (col_matrix != 4'b1111) begin
                        debounce_counter <= 0;
                        state <= DEBOUNCE;
                    end else begin
                        row_scan_counter <= (row_scan_counter == 3) ? 0 : row_scan_counter + 1;
                        state <= SET_ROW;
                    end
                end

                DEBOUNCE: begin
                    if (col_matrix != 4'b1111) begin
                        if (debounce_counter < DEBOUNCE_TIME) begin
                            debounce_counter <= debounce_counter + 1;
                        end else begin
                            // LÓGICA DE DECODIFICAÇÃO AJUSTADA PARA A SUA FIAÇÃO
                            case(row_scan_counter)
                                // Linha 0 (teclas F, 0, E, D)
                                2'b00: case(col_matrix)
                                    4'b1110: key_code_reg <= 4'hD;// 
                                    4'b1101: key_code_reg <= 4'hE;// 
                                    4'b1011: key_code_reg <= 4'h0;//
                                    4'b0111: key_code_reg <= 4'hF;// 
                                    default: key_code_reg <= 4'hA;
                                endcase
                                
                                // Linha 1 (teclas 7, 8, 9, C)
                                2'b01: case(col_matrix)
                                    4'b1110: key_code_reg <= 4'hC;//
                                    4'b1101: key_code_reg <= 4'h9;// 
                                    4'b1011: key_code_reg <= 4'h8;// 
                                    4'b0111: key_code_reg <= 4'h7;//
                                    default: key_code_reg <= 4'hA;
                                endcase
                                
                                // Linha 2 (teclas 4, 5, 6, B)
                                2'b10: case(col_matrix)
                                    4'b1110: key_code_reg <= 4'hB;// 
                                    4'b1101: key_code_reg <= 4'h6;// 
                                    4'b1011: key_code_reg <= 4'h5;// 
                                    4'b0111: key_code_reg <= 4'h4;// 
                                    default: key_code_reg <= 4'hA;
                                endcase
                                
                                // Linha 3 (teclas 1, 2, 3, A)
                                2'b11: case(col_matrix)
                                    4'b1110: key_code_reg <= 4'hA; // 
                                    4'b1101: key_code_reg <= 4'h3; //
                                    4'b1011: key_code_reg <= 4'h2; //
                                    4'b0111: key_code_reg <= 4'h1; //
                                    default: key_code_reg <= 4'hA;
                                endcase
                            endcase
                            
                            tecla_valid <= 1;
                            state <= HOLD_KEY;
                        end
                    end else begin
                        state <= READ_COLS;
                    end
                end
                
                HOLD_KEY: begin
                    if (col_matrix == 4'b1111) begin
                        state <= IDLE;
                    end
                end
                
                default: state <= IDLE;
            endcase
        end
    end
endmodule

module SixDigit7SegCtrl (
    input logic clk, 
    input logic rst,
    input logic enable,
    input bcdPac_t bcd_packet,
    output logic [6:0] HEX0, HEX1, HEX2, HEX3, HEX4, HEX5
);
    bcdPac_t bcd_reg;

    // Registra o valor do pacote BCD quando habilitado
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            bcd_reg <= '{default: 4'hB}; // Apaga todos os displays
        end else if (enable) begin
            bcd_reg <= bcd_packet;
        end
    end
    
    // Instancia um conversor para cada um dos 6 displays
    BCDto7SEGMENT conv0 (.bcd(bcd_reg.BCD0), .Seg(HEX0));
    BCDto7SEGMENT conv1 (.bcd(bcd_reg.BCD1), .Seg(HEX1));
    BCDto7SEGMENT conv2 (.bcd(bcd_reg.BCD2), .Seg(HEX2));
    BCDto7SEGMENT conv3 (.bcd(bcd_reg.BCD3), .Seg(HEX3));
    BCDto7SEGMENT conv4 (.bcd(bcd_reg.BCD4), .Seg(HEX4));
    BCDto7SEGMENT conv5 (.bcd(bcd_reg.BCD5), .Seg(HEX5));
endmodule

module resetHold5s #(parameter TIME_TO_RST = 5)(
	input 	logic clk,      // Entrada de clock de 50MHz
	input 	logic reset_in, // Sinal de reset vindo do botão
	output 	logic reset_out // Saída de reset qualificada
);

	// Constante para a frequência do clock para clareza
	localparam CLK_FREQ = 50_000_000;

	// Contador para os ciclos do clock de 50MHz. Precisa de 26 bits para contar até 50 milhões.
	logic [$clog2(CLK_FREQ)-1:0] clk_counter;

	// Contador para os segundos. Precisa de 3 bits para contar até 5.
	logic [$clog2(TIME_TO_RST+1)-1:0] sec_counter;

	// Lógica síncrona para os contadores
	always_ff @(posedge clk) begin
		if (!reset_in) begin
			// Se o botão de reset for solto, zera ambos os contadores.
			clk_counter <= '0;
			sec_counter <= '0;
		end else begin
			// Se o botão estiver pressionado, continua a contagem.
			if (sec_counter < TIME_TO_RST) begin
				if (clk_counter == CLK_FREQ - 1) begin
					// Atingiu 1 segundo
					clk_counter <= '0; // Zera o contador de ciclos
					sec_counter <= sec_counter + 1; // Incrementa o contador de segundos
				end else begin
					// Ainda não completou 1 segundo, incrementa o contador de ciclos
					clk_counter <= clk_counter + 1;
				end
			end
			// Se sec_counter atingir TIME_TO_RST, ele para de contar até que reset_in seja liberado.
		end
	end

	// A saída 'reset_out' é ativada quando o contador de segundos atinge o tempo desejado.
	assign reset_out = (sec_counter >= TIME_TO_RST);
	
endmodule



