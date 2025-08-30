// Módulo: setup
// Descrição: Gerencia o modo de configuração da fechadura.
// Correções:
// 1. Lógica do sinal 'setup_end' ajustada para ser um pulso único no final.
// 2. Ordem de exibição dos PINs alinhada com o modo operacional.

module setup (
  input  logic        clk,
  input  logic        rst,            
  input  logic        key_valid,
  input  logic [3:0]  key_code,       
  output bcdPac_t     bcd_out,
  output logic        bcd_enable,     
  output setupPac_t   data_setup_new, 
  input  setupPac_t   data_setup_old, 
  input  logic        setup_on,
  output logic        setup_end
);

  // Constantes
  localparam logic [3:0] KC_STAR = 4'hF;
  localparam integer MIN_T = 5;
  localparam integer MAX_T = 60;

  typedef enum logic [5:0] {
    S_IDLE,
    S_LOAD_OLD,
    // 01
    S_BIP_TOGGLE_SHOW,
    S_BIP_TOGGLE_WAIT,
    // 02
    S_BIP_TIME_SHOW,
    S_BIP_TIME_EDIT,
    // 03
    S_TRAV_TIME_SHOW,
    S_TRAV_TIME_EDIT,
    // 04..10
    S_PIN1_SHOW_VAL,

    S_PIN2_SHOW_ACT,
    S_PIN2_WAIT_ACT,
    S_PIN2_SHOW_VAL,

    S_PIN3_SHOW_ACT,
    S_PIN3_WAIT_ACT,
    S_PIN3_SHOW_VAL,

    S_PIN4_SHOW_ACT,
    S_PIN4_WAIT_ACT,
    S_PIN4_SHOW_VAL,

    S_DONE
  } state_t;

  // Regs
  state_t    state, state_n;
  setupPac_t cfg, cfg_next;
  bcdPac_t   bcd_r, bcd_next;
  logic      bcd_en_c, bcd_en_r;

  // teclado
  logic [3:0] digit_in; assign digit_in = key_code;
  logic       got_digit; assign got_digit = key_valid && (key_code <= 4'd9);

  function automatic integer clamp_5_60(input integer x);
    if (x < MIN_T) return MIN_T; else if (x > MAX_T) return MAX_T; else return x;
  endfunction

  // Comb: FSM e BCD
  always_comb begin
    state_n  = state;
    cfg_next = cfg;
    bcd_next = bcd_r;
    bcd_en_c = 1'b0;
    setup_end = 1'b0; // Padrão é 0. Só será 1 no final.

    case (state)
      // ---- Início
      S_IDLE: begin
        if (setup_on) state_n = S_LOAD_OLD;
      end

      S_LOAD_OLD: begin
        cfg_next = data_setup_old;
        // 01 - Ativar BIP
        bcd_next.BCD5 = 4'd0; bcd_next.BCD4 = 4'd1;
        bcd_next.BCD3 = 4'hA; bcd_next.BCD2 = 4'hA;
        bcd_next.BCD1 = 4'hA; bcd_next.BCD0 = (cfg.bip_status ? 4'd1 : 4'd0);
        bcd_en_c = 1'b1;
        state_n = S_BIP_TOGGLE_SHOW;
      end

      // ---- 01 - BIP ON/OFF
      S_BIP_TOGGLE_SHOW: state_n = S_BIP_TOGGLE_WAIT;
      
      S_BIP_TOGGLE_WAIT: begin
        if (key_valid && (key_code == 4'd0 || key_code == 4'd1)) begin
          cfg_next.bip_status = (key_code == 4'd1);
          bcd_next.BCD0 = key_code; bcd_en_c = 1'b1;
        end else if (key_valid && key_code == KC_STAR) begin
          // 02 - Tempo BIP
          bcd_next.BCD5 = 4'd0; bcd_next.BCD4 = 4'd2;
          bcd_next.BCD3 = 4'hA; bcd_next.BCD2 = 4'hA;
          bcd_next.BCD1 = (cfg.bip_time / 10) % 10;
          bcd_next.BCD0 = (cfg.bip_time % 10);
          bcd_en_c = 1'b1; state_n = S_BIP_TIME_SHOW;
        end
      end

      // ---- 02 - Tempo BIP (dois dígitos)
      S_BIP_TIME_SHOW: state_n = S_BIP_TIME_EDIT;
      
      S_BIP_TIME_EDIT: begin
        if (got_digit) begin
          bcd_next.BCD1 = bcd_r.BCD0;
          bcd_next.BCD0 = digit_in; bcd_en_c = 1'b1;
        end else if (key_valid && key_code == KC_STAR) begin
          integer val;
          val = 10*bcd_r.BCD1 + bcd_r.BCD0; val = clamp_5_60(val);
          cfg_next.bip_time = val[6:0];
          // 03 - Tempo Fechamento Automático
          bcd_next.BCD5 = 4'd0; bcd_next.BCD4 = 4'd3;
          bcd_next.BCD3 = 4'hA; bcd_next.BCD2 = 4'hA;
          bcd_next.BCD1 = (cfg.tranca_aut_time / 10) % 10;
          bcd_next.BCD0 = (cfg.tranca_aut_time % 10);
          bcd_en_c = 1'b1; state_n = S_TRAV_TIME_SHOW;
        end
      end

      // ---- 03 - Tempo Fechamento Automático (dois dígitos)
      S_TRAV_TIME_SHOW: state_n = S_TRAV_TIME_EDIT;
      
      S_TRAV_TIME_EDIT: begin
        if (got_digit) begin
          bcd_next.BCD1 = bcd_r.BCD0;
          bcd_next.BCD0 = digit_in; bcd_en_c = 1'b1;
        end else if (key_valid && key_code == KC_STAR) begin
          integer val;
          val = 10*bcd_r.BCD1 + bcd_r.BCD0; val = clamp_5_60(val);
          cfg_next.tranca_aut_time = val[6:0];
          // 04 - Senha Padrão 1 (PIN1 é sempre ativo)
          bcd_next.BCD5 = 4'd0; bcd_next.BCD4 = 4'd4;
          bcd_next.BCD3 = cfg.pin1.digit1; bcd_next.BCD2 = cfg.pin1.digit2;
          bcd_next.BCD1 = cfg.pin1.digit3; bcd_next.BCD0 = cfg.pin1.digit4;
          bcd_en_c = 1'b1;
          state_n = S_PIN1_SHOW_VAL;
        end
      end

      // ---- 04 - Senha 1 (edita valor)
      S_PIN1_SHOW_VAL: begin
        if (got_digit) begin
          bcd_next.BCD3 = bcd_r.BCD2; bcd_next.BCD2 = bcd_r.BCD1;
          bcd_next.BCD1 = bcd_r.BCD0; bcd_next.BCD0 = digit_in; bcd_en_c = 1'b1;
        end else if (key_valid && key_code == KC_STAR) begin
          cfg_next.pin1.status = 1'b1; // sempre ativo
          cfg_next.pin1.digit1 = bcd_r.BCD3; cfg_next.pin1.digit2 = bcd_r.BCD2;
          cfg_next.pin1.digit3 = bcd_r.BCD1; cfg_next.pin1.digit4 = bcd_r.BCD0;
          // 05 - Ativar senha 2
          bcd_next.BCD5 = 4'd0; bcd_next.BCD4 = 4'd5;
          bcd_next.BCD3 = 4'hA; bcd_next.BCD2 = 4'hA; bcd_next.BCD1 = 4'hA;
          bcd_next.BCD0 = (cfg.pin2.status ? 4'd1 : 4'd0);
          bcd_en_c = 1'b1; state_n = S_PIN2_SHOW_ACT;
        end
      end

      // ---- 05 - Ativar Senha 2
      S_PIN2_SHOW_ACT: state_n = S_PIN2_WAIT_ACT;
      
      S_PIN2_WAIT_ACT: begin
        if (key_valid && (key_code == 4'd0 || key_code == 4'd1)) begin
          cfg_next.pin2.status = (key_code == 4'd1);
          bcd_next.BCD0 = key_code; bcd_en_c = 1'b1;
        end else if (key_valid && key_code == KC_STAR) begin
          // 06 - Senha 2 (valor atual)
          bcd_next.BCD5 = 4'd0; bcd_next.BCD4 = 4'd6;
          bcd_next.BCD3 = cfg.pin2.digit1; bcd_next.BCD2 = cfg.pin2.digit2;
          bcd_next.BCD1 = cfg.pin2.digit3; bcd_next.BCD0 = cfg.pin2.digit4;
          bcd_en_c = 1'b1;
          state_n = S_PIN2_SHOW_VAL;
        end
      end

      // ---- 06 - Senha 2 (editar 4 dígitos)
      S_PIN2_SHOW_VAL: begin
        if (got_digit) begin
          bcd_next.BCD3 = bcd_r.BCD2; bcd_next.BCD2 = bcd_r.BCD1;
          bcd_next.BCD1 = bcd_r.BCD0; bcd_next.BCD0 = digit_in;
          bcd_en_c = 1'b1;
        end else if (key_valid && key_code == KC_STAR) begin
          cfg_next.pin2.digit1 = bcd_r.BCD3; cfg_next.pin2.digit2 = bcd_r.BCD2;
          cfg_next.pin2.digit3 = bcd_r.BCD1; cfg_next.pin2.digit4 = bcd_r.BCD0;
          // 07 - Ativar senha 3
          bcd_next.BCD5 = 4'd0; bcd_next.BCD4 = 4'd7;
          bcd_next.BCD3 = 4'hA; bcd_next.BCD2 = 4'hA; bcd_next.BCD1 = 4'hA;
          bcd_next.BCD0 = (cfg.pin3.status ? 4'd1 : 4'd0);
          bcd_en_c = 1'b1; state_n = S_PIN3_SHOW_ACT;
        end
      end

      // ---- 07 - Ativar Senha 3
      S_PIN3_SHOW_ACT: state_n = S_PIN3_WAIT_ACT;
      
      S_PIN3_WAIT_ACT: begin
        if (key_valid && (key_code == 4'd0 || key_code == 4'd1)) begin
          cfg_next.pin3.status = (key_code == 4'd1);
          bcd_next.BCD0 = key_code; bcd_en_c = 1'b1;
        end else if (key_valid && key_code == KC_STAR) begin
          // 08 - Senha 3 (valor atual)
          bcd_next.BCD5 = 4'd0; bcd_next.BCD4 = 4'd8;
          bcd_next.BCD3 = cfg.pin3.digit1; bcd_next.BCD2 = cfg.pin3.digit2;
          bcd_next.BCD1 = cfg.pin3.digit3; bcd_next.BCD0 = cfg.pin3.digit4;
          bcd_en_c = 1'b1;
          state_n = S_PIN3_SHOW_VAL;
        end
      end

      // ---- 08 - Senha 3 (editar 4 dígitos)
      S_PIN3_SHOW_VAL: begin
        if (got_digit) begin
          bcd_next.BCD3 = bcd_r.BCD2; bcd_next.BCD2 = bcd_r.BCD1;
          bcd_next.BCD1 = bcd_r.BCD0; bcd_next.BCD0 = digit_in; bcd_en_c = 1'b1;
        end else if (key_valid && key_code == KC_STAR) begin
          cfg_next.pin3.digit1 = bcd_r.BCD3; cfg_next.pin3.digit2 = bcd_r.BCD2;
          cfg_next.pin3.digit3 = bcd_r.BCD1; cfg_next.pin3.digit4 = bcd_r.BCD0;
          // 09 - Ativar senha 4
          bcd_next.BCD5 = 4'd0; bcd_next.BCD4 = 4'd9;
          bcd_next.BCD3 = 4'hA; bcd_next.BCD2 = 4'hA; bcd_next.BCD1 = 4'hA;
          bcd_next.BCD0 = (cfg.pin4.status ? 4'd1 : 4'd0);
          bcd_en_c = 1'b1; state_n = S_PIN4_SHOW_ACT;
        end
      end

      // ---- 09 - Ativar Senha 4
      S_PIN4_SHOW_ACT: state_n = S_PIN4_WAIT_ACT;
      
      S_PIN4_WAIT_ACT: begin
        if (key_valid && (key_code == 4'd0 || key_code == 4'd1)) begin
          cfg_next.pin4.status = (key_code == 4'd1);
          bcd_next.BCD0 = key_code; bcd_en_c = 1'b1;
        end else if (key_valid && key_code == KC_STAR) begin
          // 10 - Senha 4 (valor atual)
          bcd_next.BCD5 = 4'd1; bcd_next.BCD4 = 4'd0; // "10"
          bcd_next.BCD3 = cfg.pin4.digit1; bcd_next.BCD2 = cfg.pin4.digit2;
          bcd_next.BCD1 = cfg.pin4.digit3; bcd_next.BCD0 = cfg.pin4.digit4;
          bcd_en_c = 1'b1; state_n = S_PIN4_SHOW_VAL;
        end
      end

      // ---- 10 - Senha 4 (editar 4 dígitos)
      S_PIN4_SHOW_VAL: begin
        if (got_digit) begin
          bcd_next.BCD3 = bcd_r.BCD2; bcd_next.BCD2 = bcd_r.BCD1;
          bcd_next.BCD1 = bcd_r.BCD0; bcd_next.BCD0 = digit_in; bcd_en_c = 1'b1;
        end else if (key_valid && key_code == KC_STAR) begin
          cfg_next.pin4.digit1 = bcd_r.BCD3; cfg_next.pin4.digit2 = bcd_r.BCD2;
          cfg_next.pin4.digit3 = bcd_r.BCD1; cfg_next.pin4.digit4 = bcd_r.BCD0;
          
          // CORREÇÃO: Pulsa 'setup_end' para 1 aqui para sinalizar o fim
          setup_end = 1'b1; 
          
          bcd_next = '{default: 4'hA}; // Apaga os displays
          bcd_en_c = 1'b1;
          state_n = S_DONE;
        end
      end

      // Fim
      S_DONE: begin
        if(!setup_on) begin // Espera o módulo operacional desativar o setup
          state_n = S_IDLE;
        end
      end

      default: state_n = S_IDLE;
    endcase
  end

  // Bloco Sequencial (Registradores)
  always_ff @(posedge clk or posedge rst) begin
    if (rst) begin
      state <= S_IDLE;
      cfg <= '0;
      bcd_r <= '{default: 4'hA};
      bcd_en_r <= 1'b1;
    end else begin
      state <= state_n;
      cfg <= cfg_next;
      bcd_r <= bcd_next;
      bcd_en_r <= bcd_en_c;
    end
  end

  // Saídas
  assign data_setup_new = cfg;
  assign bcd_out        = bcd_r;
  assign bcd_enable     = bcd_en_r;

endmodule