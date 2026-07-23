//------------------------------------------------------------------------------
// genesis_snac_reader.sv
// Lector de mando SEGA Genesis/Mega Drive (3 y 6 botones, autodeteccion) sobre
// Analogizer SNAC para el core openfpga-SMS. Requiere el cable harness Genesis
// (RX+ <-> TX- cruzados):
//     DB9-7 TH/SEL  -> pin31        (SALIDA del core)
//     DB9-6 TL      -> bank0[7]     (entrada: B con SEL=1, A con SEL=0)
//   Resto igual que el cable SMS:
//     DB9-1 -> bank1[7], DB9-2 -> bank1[6] (compartidos con video DAC)
//     DB9-3 -> pin30
//     DB9-4 -> bank0[6]
//     DB9-9 TR -> bank0[5]          (C con SEL=1, Start con SEL=0)
//
// Protocolo. El pad de 6 botones cuenta FLANCOS DE BAJADA de SEL y resetea su
// contador si SEL permanece alto mas de ~1.5 ms:
//   SEL=1 (ciclos 1-3): Up Down Left Right | B C
//   SEL=0 (ciclos 1-2): Up Down  0    0    | A Start
//   SEL=0 (3er ciclo) : 0  0    0    0     | A Start   <- ID: pines 1-2 a 0
//   SEL=1 (4o ciclo)  : Z  Y    X    Mode  | B C       <- botones extendidos
//   SEL=0 (4o ciclo)  : 1  1    1    1     | A Start
// Un pad de 3 botones (74HC157 combinacional) repite el patron basico en todos
// los ciclos: la firma de ID falla y los botones extendidos se fuerzan a
// soltados. La deteccion es por tanto AUTOMATICA por muestra.
//
// Secuencia de muestreo: 8 fases de UNA LINEA cada una (~508 us NTSC), 2
// muestras por frame (SAMPLE_LINE1/2). Cada fase abre su propia ventana de
// bank1 con los pulsos snac_ch1/cap/ch2 del generador existente, capturando en
// snac_cap y devolviendo bank1 a salida en snac_ch2 ANTES del flanco de
// video_clk hacia el DAC (misma coreografia que el modo SMS, repetida por
// linea). SEL cambia al cerrar cada ventana -> casi una linea entera (~63 us)
// de asentamiento antes de la siguiente captura.
//
//   fase 0 (SEL=1): captura Up Down Left Right B C
//   fase 1 (SEL=0): captura A Start                       [flanco bajada #1]
//   fase 2 (SEL=1): -
//   fase 3 (SEL=0): -                                     [flanco bajada #2]
//   fase 4 (SEL=1): -
//   fase 5 (SEL=0): ID = (pin1==0 && pin2==0)             [flanco bajada #3]
//   fase 6 (SEL=1): si ID: captura Z Y X Mode
//   fase 7 (SEL=0): fin -> SEL=1 idle                     [flanco bajada #4]
//
// Entre muestras SEL queda alto >7 ms (lineas 48..160 y 168..40 del frame
// siguiente), muy por encima del reset de ~1.6 ms del pad: cada muestra
// arranca siempre con el contador del pad a cero.
//
// Salidas de botones ACTIVAS A NIVEL BAJO (como el pad: pull-up, pulsado=0).
// six_button=1 mientras la ultima muestra haya identificado un pad de 6
// botones (con pad de 3 botones queda a 0 y z/y/x/mode_n a 1).
//------------------------------------------------------------------------------
`default_nettype none

module genesis_snac_reader #(
    parameter [8:0] SAMPLE_LINE1 = 9'd40,
    parameter [8:0] SAMPLE_LINE2 = 9'd160
)(
    input  wire        clk,          // clk_sys
    input  wire        rst,          // reset_active (activo alto)
    input  wire        ena,          // ena_gen_snac_s (sincronizado a clk_sys)

    input  wire        ce_pix,       // enable de pixel (mismo que usa la logica SMS)
    input  wire        HS,           // hsync del core
    input  wire  [8:0] vy,           // linea vertical actual

    //Pulsos del generador de ventanas SNAC existente (clkd case block)
    input  wire        snac_ch1,     // abrir ventana: bank1 a entrada
    input  wire        snac_cap,     // capturar datos
    input  wire        snac_ch2,     // cerrar ventana: bank1 a salida

    //Entradas crudas desde los PADS fisicos del cartucho
    input  wire  [7:0] bank1_in,     // [7]<-DB9-2, [6]<-DB9-1 (asignacion empirica, ver fase 0)
    input  wire        pin30_in,     // DB9-3
    input  wire        bank0_7_in,   // DB9-6 TL (B / A)
    input  wire        bank0_6_in,   // DB9-4
    input  wire        bank0_5_in,   // DB9-9 TR (C / Start)

    //Control de pines
    output logic       sel,          // DB9-7 TH/SEL -> pin31 (salida, idle=1)
    output logic       bank1_dir,    // 1=bank1 salida (video), 0=ventana lectura

    //Estado de botones (activo bajo)
    output logic       up_n,
    output logic       down_n,
    output logic       left_n,
    output logic       right_n,
    output logic       a_n,
    output logic       b_n,
    output logic       c_n,
    output logic       start_n,
    //Botones extendidos (solo validos con pad de 6 botones detectado)
    output logic       x_n,
    output logic       y_n,
    output logic       z_n,
    output logic       mode_n,
    output logic       six_button    // 1 = pad de 6 botones identificado
);

    typedef enum logic [1:0] {ST_IDLE, ST_RUN} state_t;
    state_t state = ST_IDLE;

    logic       old_hs     = 1'b0;
    logic [2:0] phase      = 3'd0;  //fase actual de la secuencia (0..7)
    logic       line_armed = 1'b0;  //HS visto: ventana de esta linea habilitada
    logic       ph_open    = 1'b0;  //garantiza el orden ch1 -> cap -> ch2
    logic       id_ok      = 1'b0;  //firma de 6 botones vista en la fase 5
    logic [3:0] wd_lines   = 4'd0;  //watchdog: lineas desde el inicio de secuencia

    initial begin
        sel        = 1'b1;
        bank1_dir  = 1'b1;
        six_button = 1'b0;
        {up_n, down_n, left_n, right_n, a_n, b_n, c_n, start_n} = 8'hFF;
        {x_n, y_n, z_n, mode_n} = 4'hF;
    end

    always_ff @(posedge clk) begin
        if (rst || !ena) begin
            state      <= ST_IDLE;
            sel        <= 1'b1;
            bank1_dir  <= 1'b1;
            old_hs     <= 1'b0;
            phase      <= 3'd0;
            line_armed <= 1'b0;
            ph_open    <= 1'b0;
            id_ok      <= 1'b0;
            wd_lines   <= 4'd0;
            six_button <= 1'b0;
            {up_n, down_n, left_n, right_n, a_n, b_n, c_n, start_n} <= 8'hFF;
            {x_n, y_n, z_n, mode_n} <= 4'hF;
        end
        else begin
            if (ce_pix) old_hs <= HS;

            case (state)
            //------------------------------------------------------------------
            ST_IDLE: begin
                sel       <= 1'b1;
                bank1_dir <= 1'b1;
                if (((vy == SAMPLE_LINE1) || (vy == SAMPLE_LINE2))
                     && ce_pix && HS && !old_hs) begin
                    phase      <= 3'd0;
                    line_armed <= 1'b1;   //esta misma linea es la fase 0
                    ph_open    <= 1'b0;
                    id_ok      <= 1'b0;
                    wd_lines   <= 4'd0;
                    state      <= ST_RUN;
                end
            end
            //------------------------------------------------------------------
            // Una fase por linea. La ventana de bank1 se abre/cierra en TODAS
            // las fases (uniforme y ~370 ns por linea, identico al modo SMS);
            // que se capture algo depende de la fase. SEL cambia en snac_ch2,
            // tras la captura, dejando casi una linea de asentamiento.
            ST_RUN: begin
                if (ce_pix && HS && !old_hs) begin
                    line_armed <= 1'b1;   //nueva linea: rearmar ventana de la fase
                    wd_lines   <= wd_lines + 4'd1;
                end

                //Watchdog: la secuencia dura 8 lineas; si algo se descuadra,
                //abortar con SEL alto y bank1 en salida.
                if (wd_lines == 4'd12) begin
                    sel        <= 1'b1;
                    bank1_dir  <= 1'b1;
                    line_armed <= 1'b0;
                    ph_open    <= 1'b0;
                    state      <= ST_IDLE;
                end
                else if (line_armed) begin
                    if (snac_ch1) begin
                        bank1_dir <= 1'b0;
                        ph_open   <= 1'b1;
                    end
                    else if (snac_cap && ph_open) begin
                        case (phase)
                        //fase 0, SEL=1: estado basico del pad.
                        //Asignacion empirica heredada del modo SMS: fisicamente
                        //bank1[7] <- DB9-2 y bank1[6] <- DB9-1 (el par D-/D+ va
                        //cruzado en la cadena SNAC). Si Up/Down salen invertidos
                        //en tu montaje, intercambia [7] y [6] aqui Y en las
                        //fases 5 y 6.
                        3'd0: begin
                            down_n  <= bank1_in[7];   // DB9-2 Down
                            up_n    <= bank1_in[6];   // DB9-1 Up
                            left_n  <= pin30_in;      // DB9-3 Left
                            right_n <= bank0_6_in;    // DB9-4 Right
                            b_n     <= bank0_7_in;    // TL con SEL=1 -> B
                            c_n     <= bank0_5_in;    // TR con SEL=1 -> C
                        end
                        //fase 1, SEL=0: A y Start (bank0, la ventana de bank1
                        //no es necesaria pero es inocua).
                        3'd1: begin
                            a_n     <= bank0_7_in;    // TL con SEL=0 -> A
                            start_n <= bank0_5_in;    // TR con SEL=0 -> Start
                        end
                        //fase 5, 3er SEL=0: firma de pad de 6 botones, los
                        //pines 1-2 (Up/Down) leen 0 simultaneamente.
                        3'd5: begin
                            id_ok   <= (~bank1_in[7]) & (~bank1_in[6]);
                        end
                        //fase 6, 4o SEL=1: botones extendidos en pines 1-4
                        //(DB9-1=Z, DB9-2=Y, DB9-3=X, DB9-4=Mode). Con la misma
                        //correspondencia fisica de la fase 0: bank1[7]<-DB9-2
                        //y bank1[6]<-DB9-1.
                        3'd6: begin
                            if (id_ok) begin
                                y_n    <= bank1_in[7];  // DB9-2 -> Y
                                z_n    <= bank1_in[6];  // DB9-1 -> Z
                                x_n    <= pin30_in;     // DB9-3 -> X
                                mode_n <= bank0_6_in;   // DB9-4 -> Mode
                            end
                        end
                        default: ; //fases 2,3,4,7: sin captura
                        endcase
                    end
                    else if (snac_ch2 && ph_open) begin
                        bank1_dir  <= 1'b1;   //bank1 de vuelta al video
                        ph_open    <= 1'b0;
                        line_armed <= 1'b0;   //fase completada; esperar HS siguiente

                        if (phase == 3'd7) begin
                            //fin de secuencia: SEL idle alto, publicar deteccion
                            sel        <= 1'b1;
                            six_button <= id_ok;
                            if (!id_ok) {x_n, y_n, z_n, mode_n} <= 4'hF;
                            state      <= ST_IDLE;
                        end
                        else begin
                            //SEL de la fase siguiente: fase par->SEL=1, impar->SEL=0.
                            //Tras la fase p, la fase p+1 necesita SEL = p[0]:
                            //  tras 0 -> 0 (bajada #1), tras 1 -> 1,
                            //  tras 2 -> 0 (bajada #2), ... tras 6 -> 0 (bajada #4)
                            sel   <= phase[0];
                            phase <= phase + 3'd1;
                        end
                    end
                end
            end
            //------------------------------------------------------------------
            default: state <= ST_IDLE;
            endcase
        end
    end

endmodule
`default_nettype wire
