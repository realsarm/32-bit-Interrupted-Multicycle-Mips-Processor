`timescale 1ns / 1ps

// ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~ //
// ~~~~~~~~~~~~~~~~~~~ CONTROLLER ~~~~~~~~~~~~~~~~~~~ //
// ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~ //

module controller(opcode, clk, reset, PCWrite, Branch, DMEMWrite, IRWrite,
                   MemtoReg, PCSource, ALUSel, ALUSrcA, ALUSrcB, RegWrite,
                   RegReadSel, NMI, INT, INA, INTD,
                   datapathPCout,
                   datapathEPCin, datapathCauseInterruptin,
                   datapathPCin);


  // ~~~~~~~~~~~~~~~~~~~ PARAMETERS ~~~~~~~~~~~~~~~~~~~ //

  parameter word_size = 32;
  parameter cause_size = 2;
  integer a;
  
  // ~~~~~~~~~~~~~~~~~~~ PORTS ~~~~~~~~~~~~~~~~~~~ //

  // opcode, clock, and reset inputs
  input [5:0] opcode;	// from instruction register
  input	clk, reset;
  input NMI;
  input INT;
  input INTD;
  input [word_size-1:0] datapathPCout;

  // control signal outputs
  output reg PCWrite, Branch, DMEMWrite, IRWrite, ALUSrcA, RegWrite, RegReadSel;
  output reg [1:0] MemtoReg, PCSource, ALUSrcB;
  output reg [3:0] ALUSel;
  output reg INA;
  output reg [word_size-1:0] datapathEPCin;
  output reg [word_size-1:0] datapathPCin;
  output reg [cause_size-1:0] datapathCauseInterruptin;

  // ~~~~~~~~~~~~~~~~~~~ REGISTER ~~~~~~~~~~~~~~~~~~~ //

  // 4-bit state register
  reg [3:0]	state;
  // 1-bit NMI holder register
  reg NMIreg;
  // 1-bit INT holder register
  reg INTreg;

  // ~~~~~~~~~~~~~~~~~~~ PARAMETERS ~~~~~~~~~~~~~~~~~~~ //

  // state parameters
  parameter s0  = 4'd0;
  parameter s1  = 4'd1;
  parameter s2  = 4'd2;
  parameter s3  = 4'd3;
  parameter s4  = 4'd4;
  parameter s5  = 4'd5;
  parameter s6  = 4'd6;
  parameter s7  = 4'd7;
  parameter s8  = 4'd8;
  parameter s9  = 4'd9;
  parameter s10 = 4'd10;
  parameter s11 = 4'd11;
  parameter s12 = 4'd12;
  parameter sR  = 4'd13;	// reset
  parameter s14 = 4'd14;
  parameter sI  = 4'd15;

  // opcode[5:4] parameters
  parameter J  = 2'b00;	// Jump or NOP
  parameter R  = 2'b01;	// R-type
  parameter BR = 2'b10;	// Branch
  parameter I  = 2'b11;	// I-type

  // I-type opcode[3:0] variations
  parameter ADDI = 4'b0010;
  parameter SUBI = 4'b0011;
  parameter ORI	 = 4'b0100;
  parameter ANDI = 4'b0101;
  parameter XORI = 4'b0110;
  parameter SLTI = 4'b0111;
  parameter LI	 = 4'b1001;
  parameter LUI	 = 4'b1010;
  parameter LWI	 = 4'b1011;
  parameter SWI	 = 4'b1100;
  parameter SW   = 4'b1110;
  parameter LW   = 4'b1101;

  // ~~~~~~~~~~~~~~~~~~~ STATE MACHINE ~~~~~~~~~~~~~~~~~~~ //
  
  // hold INT To handle after instruction execution
  always @(INT) begin
    if (INT == 1'b1 && INTD == 1'b0) begin
      INTreg <= INT;
    end
    if (INT == 1'b1) begin
      INA <= 1'b1;
    end
    if (INT == 1'b0) begin
      INA <= 1'b0;
    end
  end

  // hold NMI To handle after instruction execution
  always @(NMI) begin
    if (NMI == 1'b1) begin
      NMIreg <= NMI;
    end
  end


  // control state machine
  always @(posedge clk) begin

    // check for reset signal. If set, write zero to PC and switch to Reset State on next CC.
    if (reset) begin
      PCWrite 		<= 1;
      Branch        <= 0;
      DMEMWrite 	<= 0;
      IRWrite 		<= 0;
      MemtoReg 		<= 0;
      PCSource 		<= 2'b11; // reset
      ALUSel 	    <= 0;
      ALUSrcA 		<= 0;
      ALUSrcB 		<= 0;
      RegWrite 		<= 0;
      datapathCauseInterruptin <= 2'b00;
      datapathEPCin <= {32{1'b0}};
      datapathPCin <= {32{1'b0}};
      INA <= 1'b0;
      NMIreg <= 1'b0;
      INTreg <= 1'b0;

      state <= sR;
    end
    else begin	// if reset signal is not set, check state at pos edge
      case (state)

        // if in reset state (and reset signal not set), go to s0 (IF)
        sR: begin
          PCWrite 		<= 1;
          DMEMWrite 	<= 0;
          IRWrite 		<= 1;
          PCSource 		<= 2'b00;
          ALUSel 	    <= 4'b0010;
          ALUSrcA 		<= 0;
          ALUSrcB 		<= 2'b01;
          RegWrite 		<= 0;
          Branch        <= 0;

          state <= s0;
        end

        // if in s0, go to s1 (ID)
        s0: begin
          PCWrite 		<= 0;
          DMEMWrite 	<= 0;
          IRWrite 		<= 0;
          ALUSel 		<= 4'b0010;
          ALUSrcA 		<= 0;
          ALUSrcB 		<= 2'b10;
          RegWrite 		<= 0;
          //RegReadSel	<= 0;
          datapathCauseInterruptin <= 2'b00;

          state <= s1;
        end

        // if in s1 (ID) check opcode from instruction register to determine new state
        s1: begin
          case (opcode[5:4])
            // R-type opcode: go to s2 (R-type EX)
            R: begin
              PCWrite 		<= 0;
              DMEMWrite 	<= 0;
              IRWrite 		<= 0;
              ALUSel 		<= opcode[3:0];
              ALUSrcA 		<= 1;
              ALUSrcB 		<= 2'b00;
              RegWrite 		<= 0;
              RegReadSel    <= 1;

              state <= s2;
            end

            // J-type or NOP
            J: begin
              // NOP: do nothing and go back to s0 (IF) for next instruction
              if (opcode[3:0] == 4'b0000) begin

                if ((NMIreg == 1) || (INTreg == 1 && INTD == 0)) begin
                  state	<= sI;
                end else begin
                  state	<= 0;
                  PCWrite 		<= 1;
                  DMEMWrite 	<= 0;
                  IRWrite 		<= 1;
                  PCSource 		<= 2'b00;
                  ALUSel 		<= 4'b0010;
                  ALUSrcA 		<= 0;
                  ALUSrcB 		<= 2'b01;
                  RegWrite 		<= 0;
                  Branch        <= 0;
                end
              end
              // Jump: go to s12 (jump completion)
              else begin
                PCWrite 		<= 1;
                DMEMWrite 	    <= 0;
                IRWrite 		<= 0;
                PCSource 		<= 2'b10;
                RegWrite 		<= 0;

                state <= s12;
              end
            end

            // Branch: go to s14 ($R1 read)
            BR: begin
              PCWrite 		<= 0;
              DMEMWrite 	<= 0;
              IRWrite 		<= 0;
              ALUSel 		<= 4'b0010;
              ALUSrcA 		<= 0;
              ALUSrcB 		<= 2'b10;
              RegWrite 		<= 0;
              RegReadSel    <= 0;
              //RegReadSel	<= 1; // for R1

              state <= s14;
            end

            // I-type
            I: begin
            // go to s3 (EX for ALU I-type with sign extended immediate)
              if ((opcode[3:0] == ADDI) || (opcode[3:0] == SUBI) || (opcode[3:0] == SLTI)) begin
                PCWrite 		<= 0;
                DMEMWrite 	    <= 0;
                IRWrite 	 	<= 0;
                ALUSel 			<= opcode[3:0];
                ALUSrcA 		<= 1;
                ALUSrcB 		<= 2'b10;
                RegWrite 		<= 0;
                RegReadSel      <= 0;

                state <= s3;
              end

              // go to s4 (EX for ALU I-type with zero extended immediate)
              else if ((opcode[3:0] == SW) || (opcode[3:0] == LW)) begin
                PCWrite 		<= 0;
                DMEMWrite 	    <= 0;
                IRWrite 		<= 0;
                ALUSel 			<= 4'b0010;
                ALUSrcA 		<= 1;
                ALUSrcB 		<= 2'b10;
                RegWrite 		<= 0;
                RegReadSel      <= 0;

                state <= s4;
              end
            end
          endcase
        end

        // if in s2 (R-type EX) go to s6 (ALUOp write backs)
        s2: begin
          PCWrite 		<= 0;
          DMEMWrite 	<= 0;
          IRWrite 		<= 0;
          MemtoReg      <= 0;
          RegWrite 		<= 1;

          state <= s6;
        end

        // if in s3 (EX for Arithmetic I-type with sign extended Imm) go to s6 (ALUOp WB)
        s3: begin
          PCWrite 		<= 0;
          DMEMWrite 	<= 0;
          IRWrite 		<= 0;
          MemtoReg      <= 0;
          RegWrite 		<= 1;

          state <= s6;
        end

        s4: begin
          if (opcode[3:0] == SW) begin
            PCWrite         <= 0;
            DMEMWrite       <= 1;
            IRWrite         <= 0;
            RegWrite        <= 0;

            state <= s8;
          end
          else if(opcode[3:0] == LW) begin
            PCWrite     <= 0;
            DMEMWrite 	<= 0;
            IRWrite     <= 0;
            MemtoReg    <= 0;
            RegWrite    <= 1;
            RegReadSel  <= 0;
            
            state <= s5;
          end
        end

        s5: begin
              
            // go over interrupt service routine state
            if ((NMIreg == 1) || (INTreg == 1 && INTD == 0)) begin
              PCWrite 		<= 1;
              DMEMWrite 	<= 0;
              IRWrite 		<= 0;
              PCSource 		<= 2'b00;
              ALUSel 		<= 4'b0010;
              ALUSrcA 		<= 0;
              ALUSrcB 		<= 2'b01;
              RegWrite 		<= 0;
              Branch <= 0;
              state <= sI;
            end else begin
              state           <= s0;
              PCWrite         <= 1;
              DMEMWrite       <= 0;
              IRWrite         <= 1;
              PCSource        <= 2'b00;
              ALUSel          <= 4'b0010;
              ALUSrcA         <= 0;
              ALUSrcB         <= 2'b01;
              RegWrite        <= 0;
              Branch          <= 0;
            end
        end

        // if in s6 (ALUOut WB) go back to s0 (IF)
        s6: begin
          
          // go over interrupt service routine state
          if ((NMIreg == 1) || (INTreg == 1 && INTD == 0)) begin
            PCWrite 		<= 1;
            DMEMWrite 	<= 0;
            IRWrite 		<= 0;
            PCSource 		<= 2'b00;
            ALUSel 		<= 4'b0010;
            ALUSrcA 		<= 0;
            ALUSrcB 		<= 2'b01;
            RegWrite 		<= 0;
            Branch <= 0;
            state <= sI;
          end else begin
            state           <= s0;
            PCWrite 		<= 1;
            DMEMWrite 	    <= 0;
            IRWrite 		<= 1;
            PCSource 		<= 2'b00;
            ALUSel 			<= 4'b0010;
            ALUSrcA 		<= 0;
            ALUSrcB 		<= 2'b01;
            RegWrite 		<= 0;
            Branch          <= 0;
          end
        end

        // if in s8 (MEM write for SWI) go to s0 (IF)
        s8: begin

          // go over interrupt service routine state
          if ((NMIreg == 1) || (INTreg == 1 && INTD == 0)) begin
            PCWrite 		<= 1;
            DMEMWrite 	<= 0;
            IRWrite 		<= 0;
            PCSource 		<= 2'b00;
            ALUSel 		<= 4'b0010;
            ALUSrcA 		<= 0;
            ALUSrcB 		<= 2'b01;
            RegWrite 		<= 0;
            Branch <= 0;
            state <= sI;
          end else begin
            state           <= s0;
            PCWrite 		<= 1;
            DMEMWrite 	    <= 0;
            IRWrite 		<= 1;
            PCSource 		<= 2'b00;
            ALUSel 			<= 4'b0010;
            ALUSrcA 		<= 0;
            ALUSrcB 		<= 2'b01;
            RegWrite 		<= 0;
            Branch          <= 0;
          end
        end

        // if in s11 (Branch completion) go to s0 (IF)
        s11: begin

          // go over interrupt service routine state
          if ((NMIreg == 1) || (INTreg == 1 && INTD == 0)) begin
            PCWrite 		<= 1;
            DMEMWrite 	<= 0;
            IRWrite 		<= 0;
            PCSource 		<= 2'b00;
            ALUSel 		<= 4'b0010;
            ALUSrcA 		<= 0;
            ALUSrcB 		<= 2'b01;
            RegWrite 		<= 0;
            Branch <= 0;
            state <= sI;
          end else begin
            state <= s0;
            PCWrite 		<= 1;
            DMEMWrite 	    <= 0;
            IRWrite 		<= 1;
            PCSource 		<= 2'b00;
            ALUSel 			<= 4'b0010;
            ALUSrcA 		<= 0;
            ALUSrcB 		<= 2'b01;
            RegWrite 		<= 0;
            Branch          <= 0;
          end
        end

        // if in s12 (Jump completion) go to s0 (IF)
        s12: begin

          // go over interrupt service routine state
          if ((NMIreg == 1) || (INTreg == 1 && INTD == 0)) begin
            PCWrite 		<= 1;
            DMEMWrite 	<= 0;
            IRWrite 		<= 0;
            PCSource 		<= 2'b00;
            ALUSel 		<= 4'b0010;
            ALUSrcA 		<= 0;
            ALUSrcB 		<= 2'b01;
            RegWrite 		<= 0;
            Branch <= 0;
            state <= sI;
          end else begin
            state <= s0;
            PCWrite 		<= 1;
            DMEMWrite 	    <= 0;
            IRWrite 		<= 1;
            PCSource 		<= 2'b00;
            ALUSel 			<= 4'b0010;
            ALUSrcA 		<= 0;
            ALUSrcB 		<= 2'b01;
            RegWrite 		<= 0;
            Branch          <= 0;
          end
        end

        // if in R1 read
        s14: begin
          // if Branch, go to s11, branch completion
          if (opcode[5:4] == BR) begin
            PCWrite 		<= 0;
            Branch          <= 1;
            DMEMWrite 	    <= 0;
            IRWrite 		<= 0;
            PCSource 		<= 2'b01;
            ALUSel 			<= 4'b0011;
            ALUSrcA 		<= 1;
            ALUSrcB 		<= 2'b00;
            RegWrite 		<= 0;
            //RegReadSel	<= 1;

            state <= s11;
          end
        end
        // interrupt service routine state
        // NMI -> 01
        // INT -> 10
        sI: begin
          datapathEPCin <= datapathPCout;
          a = datapathEPCin ;
          datapathPCin <= 32'd64;
          #15
          datapathPCin <= a;
          #5
          datapathPCin <= 32'd0;


          PCWrite 		<= 1;
          DMEMWrite 	<= 0;
          IRWrite 		<= 1;
          PCSource 		<= 2'b00;
          ALUSel 		<= 4'b0010;
          ALUSrcA 		<= 0;
          ALUSrcB 		<= 2'b01;
          RegWrite 		<= 0;
          Branch <= 0;
          if (NMI == 1) begin
            datapathCauseInterruptin <= 2'b01;
          end
          else if ((NMI == 1) && (INT == 1)) begin
            datapathCauseInterruptin <= 2'b01;
          end
          else if (INT == 1) begin
            datapathCauseInterruptin <= 2'b10;
          end
          NMIreg <= 1'b0;
          INTreg <= 1'b0;

          state <= s0;
        end
        // go to s0
        default: begin
          PCWrite 		<= 1;
          DMEMWrite 	<= 0;
          IRWrite 		<= 1;
          PCSource 		<= 2'b00;
          ALUSel 		<= 4'b0010;
          ALUSrcA 		<= 0;
          ALUSrcB 		<= 2'b01;
          RegWrite 		<= 0;
          Branch <= 0;

          state <= s0;
        end
      endcase
    end
  end
endmodule
