module IF_stage(
    input               clk,
    input               rst,
    input               branch_taken_in,
    input               freeze_in,
    input       [31:0]  branch_address_in,

    output      [31:0]  pc_plus_four_out,
    output reg  [31:0]  instruction_mem_out
);

    reg         [31:0]  pc_reg_out;

    wire        [31:0]  pc_reg_in;
    wire        [31:0]  memory_address_aligned;

    assign pc_reg_in                = (branch_taken_in) ? (branch_address_in) : (pc_plus_four_out); // pc reg input multiplexer
    assign pc_plus_four_out         = pc_reg_out + 32'd4; // pc adder
    assign memory_address_aligned   = {pc_reg_out[31:2], 2'b00};

    // pc register 
    always@(posedge clk) begin
        if (rst)                pc_reg_out <= 0;
        else if(branch_taken_in) pc_reg_out <= pc_reg_in;
        else if(freeze_in)      pc_reg_out <= pc_reg_out;
        else                    pc_reg_out <= pc_reg_in;
    end

    // instruction memory
    always @(*) begin
        instruction_mem_out <= 32'bx;
        case (memory_address_aligned)
            32'd0:      instruction_mem_out <= 32'b1110_00_1_1101_0_0000_0000_000000010100;     /*1. {true} */  //MOV		R0 ,#20 		    //R0 = 20
            32'd4:      instruction_mem_out <= 32'b1110_00_1_1101_0_0000_0001_101000000001;     /*2. {true} */  //MOV		R1 ,#4096		    //R1 = 4096
            32'd8:      instruction_mem_out <= 32'b1110_00_1_1101_0_0000_0010_000100000011;     /*3. {true} */  //MOV		R2 ,#0xC0000000	    //R2 = -1073741824
            32'd12:     instruction_mem_out <= 32'b1110_00_0_0100_1_0010_0011_000000000010;     /*4. {true} */  //ADDS		R3 ,R2,R2		    //R3 = -2147483648 
            32'd16:     instruction_mem_out <= 32'b1110_00_0_0101_0_0000_0100_000000000000;     /*5. {true} */  //ADC		R4 ,R0,R0		    //R4 = 41
            32'd20:     instruction_mem_out <= 32'b1110_00_0_0010_0_0100_0101_000100000100;     /*6. {true} */  //SUB		R5 ,R4,R4,LSL #2	//R5 = 41 - 4 * 41 = -123
            32'd24:     instruction_mem_out <= 32'b1110_00_0_0110_0_0000_0110_000010100000;     /*7. {true} */  //SBC		R6 ,R0,R0,LSR #1	//R6 = 10
            32'd28:     instruction_mem_out <= 32'b1110_00_0_1100_0_0101_0111_000101000010;     /*8. {true} */  //ORR		R7 ,R5,R2,ASR #2	//R7 = -123
            32'd32:     instruction_mem_out <= 32'b1110_00_0_0000_0_0111_1000_000000000011;     /*9. {true} */  //AND		R8 ,R7,R3		    //R8 = -2147483648
            32'd36:     instruction_mem_out <= 32'b1110_00_0_1111_0_0000_1001_000000000110;     /*10 {true} */  //MVN		R9 ,R6		        //R9 = -11
            32'd40:     instruction_mem_out <= 32'b1110_00_0_0001_0_0100_1010_000000000101;     /*11 {true} */  //EOR		R10,R4,R5	        //R10 = -84
            32'd44:     instruction_mem_out <= 32'b1110_00_0_1010_1_1000_0000_000000000110;     /*12 {true} */  //CMP		R8 ,R6		
            32'd48:     instruction_mem_out <= 32'b0001_00_0_0100_0_0001_0001_000000000001;     /*13 {true} */  //ADDNE	    R1 ,R1,R1		    //R1 = 8192
            32'd52:     instruction_mem_out <= 32'b1110_00_0_1000_1_1001_0000_000000001000;     /*14 {true} */  //TST		R9 ,R8		
            32'd56:     instruction_mem_out <= 32'b0000_00_0_0100_0_0010_0010_000000000010;     /*15 {true} */  //ADDEQ	    R2 ,R2,R2   	    //R2 = -1073741824
            32'd60:     instruction_mem_out <= 32'b1110_00_1_1101_0_0000_0000_101100000001;     /*16 {true} */  //MOV		R0 ,#1024		    //R0 = 1024
            32'd64:     instruction_mem_out <= 32'b1110_01_0_0100_0_0000_0001_000000000000;     /*17 {true} */  //STR		R1 ,[R0],#0	        //MEM[1024] = 8192
            32'd68:     instruction_mem_out <= 32'b1110_01_0_0100_1_0000_1011_000000000000;     /*18 {true} */  //LDR		R11,[R0],#0	        //R11 = MEM[1024] = 8192
            32'd72:     instruction_mem_out <= 32'b1110_01_0_0100_0_0000_0010_000000000100;     /*19 {true} */  //STR		R2 ,[R0],#4	        //MEM[1028] = -1073741824
            32'd76:     instruction_mem_out <= 32'b1110_01_0_0100_0_0000_0011_000000001000;     /*20 {true} */  //STR		R3 ,[R0],#8	        //MEM[1032] = -2147483648
            32'd80:     instruction_mem_out <= 32'b1110_01_0_0100_0_0000_0100_000000001101;     /*21 {true} */  //STR		R4 ,[R0],#13	    //MEM[1036] = 41
            32'd84:     instruction_mem_out <= 32'b1110_01_0_0100_0_0000_0101_000000010000;     /*22 {true} */  //STR		R5 ,[R0],#16	    //MEM[1040] = -123
            32'd88:     instruction_mem_out <= 32'b1110_01_0_0100_0_0000_0110_000000010100;     /*23 {true} */  //STR		R6 ,[R0],#20	    //MEM[1044] = 10
            32'd92:     instruction_mem_out <= 32'b1110_01_0_0100_1_0000_1010_000000000100;     /*24 {true} */  //LDR		R10,[R0],#4	        //R10 = -1073741824
            32'd96:     instruction_mem_out <= 32'b1110_01_0_0100_0_0000_0111_000000011000;     /*25 {true} */  //STR		R7 ,[R0],#24	    //MEM[1048] = -123
            32'd100:    instruction_mem_out <= 32'b1110_00_1_1101_0_0000_0001_000000000100;     /*26 {true} */  //MOV		R1 ,#4		        //R1 = 4
            32'd104:    instruction_mem_out <= 32'b1110_00_1_1101_0_0000_0010_000000000000;     /*27 {true} */  //MOV		R2 ,#0		        //R2 = 0
            32'd108:    instruction_mem_out <= 32'b1110_00_1_1101_0_0000_0011_000000000000;     /*28 {true} */  //MOV	-   R3 ,#0		        //R3 = 0
            32'd112:    instruction_mem_out <= 32'b1110_00_0_0100_0_0000_0100_000100000011;     /*29        */  //ADD	+   R4 ,R0,R3,LSL #2    //R4 = 1024+(0,1,2)*4=(1024,1028,1032)	
            32'd116:    instruction_mem_out <= 32'b1110_01_0_0100_1_0100_0101_000000000000;     /*30        */  //LDR		R5 ,[R4],#0         //R5 = MEM[R4]=  (8192, , , ) 
            32'd120:    instruction_mem_out <= 32'b1110_01_0_0100_1_0100_0110_000000000100;     /*31        */  //LDR		R6 ,[R4],#4         //R6 = MEM[R4+4]= (-1073741824, , , ) 
            32'd124:    instruction_mem_out <= 32'b1110_00_0_1010_1_0101_0000_000000000110;     /*32        */  //CMP		R5 ,R6              //R5-R6=(P,)=({0,0,0,0}, ) 
            32'd128:    instruction_mem_out <= 32'b1100_01_0_0100_0_0100_0110_000000000000;     /*33        */  //STRGT	    R6 ,[R4],#0         //if(z=0 & n=v) MEM[R4]<-R6 = (-1073741824, )    
            32'd132:    instruction_mem_out <= 32'b1100_01_0_0100_0_0100_0101_000000000100;     /*34        */  //STRGT	    R5 ,[R4],#4         //if(z=0 & n=v) MEM[R4+4] =   
            32'd136:    instruction_mem_out <= 32'b1110_00_1_0100_0_0011_0011_000000000001;     /*35        */  //ADD		R3 ,R3,#1           //R3=(0,1,2) + 1 = (1,2,3)           
            32'd140:    instruction_mem_out <= 32'b1110_00_1_1010_1_0011_0000_000000000011;     /*36        */  //CMP		R3 ,#3              //(1,2,3)-3=(-2,-1,0)={1,0,0,0}, {0,1,0,0} 
            32'd144:    instruction_mem_out <= 32'b1011_10_1_0_111111111111111111011100;        /*37        */  //BLT	*+  #-36                //if(n != v) jump to (+) else go next line 
            32'd148:    instruction_mem_out <= 32'b1110_00_1_0100_0_0010_0010_000000000001;     /*38        */  //ADD		R2 ,R2,#1           //R2=(0,)+1=(1,)
            32'd152:    instruction_mem_out <= 32'b1110_00_0_1010_1_0010_0000_000000000001;     /*39        */  //CMP		R2 ,R1              //R2-R1=(1,2,3,4)-4=(-3,-2,-1,0) {1,0,0,0}
            32'd156:    instruction_mem_out <= 32'b1011_10_1_0_111111111111111111001100;        /*40        */  //BLT	*-  #-52                //if(n != v) jump to (-) else go next line
            32'd160:    instruction_mem_out <= 32'b1110_01_0_0100_1_0000_0001_000000000000;     /*41 {true} */  //LDR		R1 ,[R0],#0	        //R1 = MEM[1024] = -2147483648      
            32'd164:    instruction_mem_out <= 32'b1110_01_0_0100_1_0000_0010_000000000100;     /*42 {true} */  //LDR		R2 ,[R0],#4	        //R2 = MEM[1028] = -1073741824     
            32'd168:    instruction_mem_out <= 32'b1110_01_0_0100_1_0000_0011_000000001000;     /*43 {true} */  //LDR		R3 ,[R0],#8	        //R3 = MEM[1032] = 41               
            32'd172:    instruction_mem_out <= 32'b1110_01_0_0100_1_0000_0100_000000001100;     /*44 {true} */  //LDR		R4 ,[R0],#12	    //R4 = MEM[1036] = 8192            
            32'd176:    instruction_mem_out <= 32'b1110_01_0_0100_1_0000_0101_000000010000;     /*45 {true} */  //LDR		R5 ,[R0],#16	    //R5 = MEM[1040] = -123             
            32'd180:    instruction_mem_out <= 32'b1110_01_0_0100_1_0000_0110_000000010100;     /*46 {true} */  //LDR		R6 ,[R0],#20	    //R6 = MEM[1044] = 10              
            32'd184:    instruction_mem_out <= 32'b1110_10_1_0_111111111111111111111100;        /*47        */  //B		*   #-4
            default:    instruction_mem_out <= 32'bx;
        endcase
    end

endmodule

