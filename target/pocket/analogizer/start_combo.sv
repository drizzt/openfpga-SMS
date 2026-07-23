// =============================================================================
// start_combo.sv
// -----------------------------------------------------------------------------
// Detecta la pulsación SIMULTÁNEA y MANTENIDA de dos botones (btn1 + btn2)
// durante un tiempo configurable (por defecto 0.5s) y genera un pulso de
// "Start" emulado, con la misma semántica que tendría una pulsación real
// del botón Start leído por el core (p.ej. para inyectarlo en tu lectura
// de pad vía cart_tran_bank1 en el SMS core).
//
// Características:
//   - Doble sincronizador (2FF) para evitar metaestabilidad en las entradas
//     asíncronas btn1/btn2.
//   - Debounce por conteo (evita rebotes mecánicos).
//   - Contador de "hold time" que se resetea si se suelta cualquiera de
//     los dos botones antes de completar el tiempo.
//   - Genera un pulso de ancho configurable (START_PULSE_MS) en vez de un
//     nivel, para que sea compatible con lógica que espera flanco de botón.
//   - Anti-retrigger: no se vuelve a disparar hasta que se sueltan ambos
//     botones tras un disparo.
//
// Polaridad: se asume btn1/btn2 ACTIVOS A NIVEL ALTO (1 = pulsado).
// Si tus botones son activos a nivel bajo, invierte btn1_raw/btn2_raw
// en la instanciación (~btn1_raw).
// =============================================================================

module start_combo #(
    parameter int CLK_FREQ_HZ     = 50_000_000, // frecuencia del reloj de entrada
    parameter int HOLD_MS         = 500,        // tiempo de mantenimiento requerido (ms)
    parameter int DEBOUNCE_MS     = 5,           // tiempo de estabilización anti-rebote (ms)
    parameter int START_PULSE_MS  = 100          // duración del pulso de start emulado (ms)
)(
    input  logic clk,
    input  logic rst_n,        // reset asíncrono, activo a nivel bajo

    input  logic btn1_raw,     // botón 1, activo alto, señal asíncrona externa
    input  logic btn2_raw,     // botón 2, activo alto, señal asíncrona externa

    output logic start_pulse,  // pulso emulado de Start (activo alto, START_PULSE_MS de ancho)
    output logic combo_active  // '1' mientras se está contando el hold (útil para debug/LED)
);

    // -------------------------------------------------------------------
    // Cálculo de ciclos para cada temporización
    // -------------------------------------------------------------------
    localparam int unsigned DEBOUNCE_CYCLES = (CLK_FREQ_HZ / 1000) * DEBOUNCE_MS;
    localparam int unsigned HOLD_CYCLES     = (CLK_FREQ_HZ / 1000) * HOLD_MS;
    localparam int unsigned PULSE_CYCLES    = (CLK_FREQ_HZ / 1000) * START_PULSE_MS;

    localparam int DEBOUNCE_W = $clog2(DEBOUNCE_CYCLES + 1);
    localparam int HOLD_W     = $clog2(HOLD_CYCLES + 1);
    localparam int PULSE_W    = $clog2(PULSE_CYCLES + 1);

    // -------------------------------------------------------------------
    // 1) Sincronización de entradas asíncronas (2 flip-flops)
    // -------------------------------------------------------------------
    logic btn1_sync0, btn1_sync1;
    logic btn2_sync0, btn2_sync1;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            btn1_sync0 <= 1'b0; btn1_sync1 <= 1'b0;
            btn2_sync0 <= 1'b0; btn2_sync1 <= 1'b0;
        end else begin
            btn1_sync0 <= btn1_raw;
            btn1_sync1 <= btn1_sync0;
            btn2_sync0 <= btn2_raw;
            btn2_sync1 <= btn2_sync0;
        end
    end

    // -------------------------------------------------------------------
    // 2) Debounce individual por conteo: la señal solo se considera
    //    estable cuando se mantiene constante durante DEBOUNCE_CYCLES.
    // -------------------------------------------------------------------
    logic [DEBOUNCE_W-1:0] db_cnt1, db_cnt2;
    logic btn1_deb, btn2_deb;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            db_cnt1  <= '0;
            btn1_deb <= 1'b0;
        end else if (btn1_sync1 != btn1_deb) begin
            if (db_cnt1 >= DEBOUNCE_CYCLES[DEBOUNCE_W-1:0]) begin
                btn1_deb <= btn1_sync1;
                db_cnt1  <= '0;
            end else begin
                db_cnt1 <= db_cnt1 + 1'b1;
            end
        end else begin
            db_cnt1 <= '0; // señal estable, sin cambios pendientes
        end
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            db_cnt2  <= '0;
            btn2_deb <= 1'b0;
        end else if (btn2_sync1 != btn2_deb) begin
            if (db_cnt2 >= DEBOUNCE_CYCLES[DEBOUNCE_W-1:0]) begin
                btn2_deb <= btn2_sync1;
                db_cnt2  <= '0;
            end else begin
                db_cnt2 <= db_cnt2 + 1'b1;
            end
        end else begin
            db_cnt2 <= '0;
        end
    end

    // -------------------------------------------------------------------
    // 3) Contador de "hold" del combo + anti-retrigger
    // -------------------------------------------------------------------
    logic combo_raw;
    assign combo_raw = btn1_deb & btn2_deb;

    logic [HOLD_W-1:0] hold_cnt;
    logic armed;       // '1' mientras esperamos que se suelten los botones tras disparo
    logic fire;        // pulso de 1 ciclo cuando se alcanza el tiempo de hold

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            hold_cnt <= '0;
            armed    <= 1'b0;
            fire     <= 1'b0;
        end else begin
            fire <= 1'b0; // por defecto, pulso de 1 ciclo

            if (!combo_raw) begin
                // se soltó alguno de los dos botones: reset del contador
                hold_cnt <= '0;
                armed    <= 1'b0;
            end else if (!armed) begin
                if (hold_cnt >= HOLD_CYCLES[HOLD_W-1:0]) begin
                    fire     <= 1'b1;  // ¡combo completado!
                    armed    <= 1'b1;  // bloquea nuevos disparos hasta soltar
                end else begin
                    hold_cnt <= hold_cnt + 1'b1;
                end
            end
            // si armed=1 y combo_raw sigue activo, no hacemos nada:
            // esperamos a que se suelte para poder rearmar
        end
    end

    assign combo_active = combo_raw;

    // -------------------------------------------------------------------
    // 4) Generador de pulso de Start emulado (ancho = START_PULSE_MS)
    // -------------------------------------------------------------------
    logic [PULSE_W-1:0] pulse_cnt;
    logic pulse_active;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            pulse_cnt    <= '0;
            pulse_active <= 1'b0;
        end else if (fire) begin
            pulse_active <= 1'b1;
            pulse_cnt    <= '0;
        end else if (pulse_active) begin
            if (pulse_cnt >= PULSE_CYCLES[PULSE_W-1:0]) begin
                pulse_active <= 1'b0;
            end else begin
                pulse_cnt <= pulse_cnt + 1'b1;
            end
        end
    end

    assign start_pulse = pulse_active;

endmodule