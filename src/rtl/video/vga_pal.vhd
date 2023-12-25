--------------------------------------------------------------------------------
--     : "ZXKit1 -  VGA & PAL"                  --                        
--  :  V2.0.8.08                                          : 091223  --
--  :                                                     --
--
--  Modified by Andy Karpov
--  2020-07-20: Added profi video mode support and forced switch via DS80
--  2020-07-20: Replaced ext video ram with 2-port fpga sram
--  2020-08-07: cleanup, refactoring
--------------------------------------------------------------------------------

library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.std_logic_unsigned.all;

entity VGA_PAL is
	generic 
	(
		inverse_ksi 		 : boolean := false;
		inverse_ssi 		 : boolean := false;
		inverse_f 			 : boolean := false
	);
	port
	(

--------------------------------------------------------------------------------
--                                       091103  --
--------------------------------------------------------------------------------

RGB_IN 		: in std_logic_vector(8 downto 0); -- RRRGGGBBB
DS80			: in std_logic := '0';
KSI_IN      : in std_logic := '1'; --  
SSI_IN      : in std_logic := '1'; --  
CLK         : in std_logic := '1'; --    14 / 12 
CLK2       	: in std_logic := '1'; --  CLK
EN 			: in std_logic := '1'; --       
                                      
--------------------------------------------------------------------------------
--                         VGA                    090728  --
--------------------------------------------------------------------------------

RGB_O 	  : out std_logic_vector(8 downto 0) := (others => '0'); -- VGA RGB
VSYNC_VGA  : out std_logic := '1'; --  
HSYNC_VGA  : out std_logic := '1' --  

);
    end VGA_PAL;
architecture RTL of VGA_PAL is

--------------------------------------------------------------------------------
--                                               090804  --
--------------------------------------------------------------------------------
--------------------------------------------------------------------------------
--                                       090805  --
--------------------------------------------------------------------------------

signal RGB 	  : std_logic_vector(8 downto 0);
signal RGBI_CLK : std_logic; --     

signal KSI    : std_logic; --  
signal SSI    : std_logic; --  

--------------------------------------------------------------------------------
--                                           091220  --
--------------------------------------------------------------------------------

signal KSI_1  : std_logic; --   
signal KSI_2  : std_logic; --   
signal SSI_2  : std_logic; --   

--------------------------------------------------------------------------------
--                   VGA  VIDEO        091223  --
--------------------------------------------------------------------------------
--   VGA:

signal VGA_H_CLK     : std_logic; --      
signal VGA_H         : std_logic_vector(8 downto 0); --    
signal VGA_H_MIN     : std_logic_vector(8 downto 0); -- . .. 
signal VGA_H_MAX     : std_logic_vector(8 downto 0); -- ... 
signal VGA_SSI1_BGN   : std_logic_vector(9 downto 0); --   
signal VGA_SSI1_END   : std_logic_vector(9 downto 0); --    
signal VGA_SSI2_BGN   : std_logic_vector(9 downto 0); --   
signal VGA_SSI2_END   : std_logic_vector(9 downto 0); --    
signal VGA_SGI1_BGN   : std_logic_vector(9 downto 0); --   
signal VGA_SGI1_END   : std_logic_vector(9 downto 0); --    
signal VGA_SGI2_BGN   : std_logic_vector(9 downto 0); --   
signal VGA_SGI2_END   : std_logic_vector(9 downto 0); --    
signal VGA_H0 			 : std_logic := '0';
--------------------------------------------------------------------------------
--   VGA:

signal VGA_V_CLK     : std_logic; --      
signal VGA_V         : std_logic_vector(9 downto 0); --    
signal VGA_V_MIN     : std_logic_vector(9 downto 0); -- . . 
signal VGA_V_MAX     : std_logic_vector(9 downto 0); -- .. 
signal VGA_KSI_BGN   : std_logic_vector(9 downto 0); --   
signal VGA_KSI_END   : std_logic_vector(9 downto 0); --    
signal VGA_KGI1_END  : std_logic_vector(9 downto 0); --    
signal VGA_KGI2_BGN  : std_logic_vector(9 downto 0); --   
--------------------------------------------------------------------------------
--   VIDEO:

signal VIDEO_H_CLK   : std_logic; --      
signal VIDEO_H       : std_logic_vector(9 downto 0); --    
signal VIDEO_H_MAX   : std_logic_vector(9 downto 0); -- .. . 
signal VIDEO_SSI_BGN : std_logic_vector(9 downto 0); --   
signal VIDEO_SSI_END : std_logic_vector(9 downto 0); --    
signal VIDEO_SGI_BGN : std_logic_vector(9 downto 0); --   
signal VIDEO_SGI_END : std_logic_vector(9 downto 0); --    
--------------------------------------------------------------------------------
--   VIDEO:

signal VIDEO_V_CLK   : std_logic;  --     
signal VIDEO_V       : std_logic_vector(8 downto 0); --    
signal VIDEO_V_MAX   : std_logic_vector(8 downto 0); -- .. . 
signal VIDEO_KSI_BGN : std_logic_vector(8 downto 0); --   
signal VIDEO_KSI_END : std_logic_vector(8 downto 0); --    
signal VIDEO_KGI_BGN : std_logic_vector(8 downto 0); --   
signal VIDEO_KGI_END : std_logic_vector(8 downto 0); --    
signal SCREEN_V_END  : std_logic_vector(8 downto 0); --  .  
--------------------------------------------------------------------------------
--  /   : 

--------------------------------------------------------------------------------
--                       VGA  VIDEO                 091220  --
--------------------------------------------------------------------------------

signal VGA_KSI      : std_logic; --    VGA
signal VGA_SSI      : std_logic; --    VGA

--signal VIDEO_KSI    : std_logic; --    VIDEO
--signal VIDEO_SSI1   : std_logic; --     VIDEO
--signal VIDEO_SSI2   : std_logic; --   -   VIDEO
--signal VIDEO_SYNC   : std_logic; --   VIDEO

signal VGA_RBGI_CLK : std_logic; --     VGA 

signal RESET_ZONE   : std_logic; --     
signal RESET_H      : std_logic; --  0,         
signal RESET_V      : std_logic; --  0,         
 
--------------------------------------------------------------------------------
--                       VGA  VIDEO                091102  --
--------------------------------------------------------------------------------

signal VGA_KGI      : std_logic; --     VGA
signal VGA_SGI      : std_logic; --     VGA
signal VGA_BLANK    : std_logic; --    VGA

--signal VIDEO_KGI    : std_logic; --     VIDEO
--signal VIDEO_SGI    : std_logic; --     VIDEO
--signal VIDEO_BLANK  : std_logic; --    VIDEO

--------------------------------------------------------------------------------
--                                 			 090821  --
--------------------------------------------------------------------------------

signal RD_REG       : std_logic_vector(8 downto 0);

begin

--------------------------------------------------------------------------------
--                                                                    --
--------------------------------------------------------------------------------
--------------------------------------------------------------------------------
--                                         090826  --
--------------------------------------------------------------------------------

--   /    ON, 
--    ,   .
--    
--------------------------------------------------------------------------------
RGBI_CLK <= not CLK2 when inverse_f else CLK2; --   
--------------------------------------------------------------------------------
process (RGBI_CLK, RGB_IN)   
begin
  if (falling_edge(RGBI_CLK)) then --    
      RGB <= RGB_IN;
  end if;
end process;

--------------------------------------------------------------------------------
--                              091223  --
--------------------------------------------------------------------------------
process (CLK, SSI_IN, SSI)
begin

  if (rising_edge(CLK)) then  --    ,   0  1
		if (inverse_ssi) then
			SSI   <= not SSI_IN;
		else 
			SSI   <= SSI_IN;
		end if;
      SSI_2 <= not SSI;       --     
  end if;
end process;

process (KSI, KSI_2, VGA_H, VIDEO_H, KSI_IN, SSI, SSI_2)
begin
  --       1/4...1/2  VIDEO
  if (rising_edge(VIDEO_H(8)) and VIDEO_H(9)='0') then
		if (inverse_ksi) then
			KSI   <= not KSI_IN;
		else
			KSI   <= KSI_IN;
		end if;
      KSI_2 <= not KSI;       --      
  end if;
end process;

RESET_H <= SSI or SSI_2;      --  0,         
RESET_V <= KSI or KSI_2;      --  0,     
--    , 0     -
RESET_ZONE  <= (not VIDEO_V(7) or VIDEO_V(8)); 

VGA_V_CLK   <= (VGA_H(7)   or VGA_H(8));
VIDEO_V_CLK <= (VIDEO_H(8) or VIDEO_H(9));

--------------------------------------------------------------------------------
--                                  091220  --
--------------------------------------------------------------------------------
process (CLK, DS80, RESET_H, RESET_ZONE, VGA_H_MAX, VGA_H, VIDEO_H)
begin  
  --     VGA 
  if (DS80 = '0') then
      VGA_H_MAX <= "110111111"; -- 447 (895/2) pent
  else 
	   VGA_H_MAX <= "101111111"; -- 383 (767/2) profi
  end if;

  if (falling_edge(CLK)) then          -- ,    :

    --           -:
    --      
    if (RESET_H or RESET_ZONE) = '0'  then
      VGA_H     <= (others => '0');    --    VGA
      VIDEO_H   <= (others => '0');    --    VIDEO
      
    else                               --  -  :
   
      if (VGA_H = VGA_H_MAX) then      --      VGA,
        VGA_H   <= (others => '0');    --    VGA
      else
        VGA_H   <= VGA_H + 1;          --  -   
      end if;    

      if (VIDEO_H = (VGA_H_MAX & "1")) then --  .    VIDEO,
        VIDEO_H <= (others => '0');    --    VGA
      else
        VIDEO_H <= VIDEO_H + 1;        --  -   
      end if;    

   end if;   
  end if;   
end process;

--------------------------------------------------------------------------------
--                                     091223  --
--------------------------------------------------------------------------------

process (VGA_V_CLK, RESET_V, VIDEO_V_CLK, VIDEO_V)
begin
--------------------------------------------------------------------------------
--   VGA:
  if (falling_edge(VGA_V_CLK)) then  --     . 

    --    48/50 
      if (RESET_V) = '0' then        --    :
        VGA_V <= (others => '0');    --    VGA
      else                           --  
        VGA_V <= VGA_V   + 1;        --    VGA
      end if;    
  end if;    
--------------------------------------------------------------------------------
--   VIDEO:
  if (falling_edge(VIDEO_V_CLK)) then --     .
    if (RESET_V) = '0' then           --    :
      VIDEO_V <= (others => '0');     --    VIDEO
    else    
      VIDEO_V <= VIDEO_V + 1;         --    VIDEO
    end if;    
  end if;    
-------------------------------------------------------------------------------
end process;

--------------------------------------------------------------------------------
--                   VGA               091223  --
--------------------------------------------------------------------------------
--    VGA:
--  : 768   608 ,  896   640 .
--  : 608   544 ,  768   624 .

--   
--   ,  ,       1   2,  

process (DS80)                   
begin
  case DS80 is
 
    when '0' =>   -- ""
      --   VGA:
      VGA_SSI1_BGN <= "0000000000"; --   0 -  1  
      VGA_SSI1_END <= "0000100110"; --  38 -   1  
      VGA_SGI1_END <= "0001001001"; -- 73 -   1   65 + 48 - 24 - 8 missing
      VGA_SGI2_BGN <= "1101010001"; -- 849 -  2  
      VGA_SSI2_BGN <= "1101111011"; -- 891 -  2  
      VGA_SSI2_END <= "1101111111"; -- 895 -   2   --  

    when '1' =>   -- ""
      VGA_SSI1_BGN <= "0000000000"; --   0 -  1  
      VGA_SSI1_END <= "0000100010"; --  34 -   1  
      VGA_SGI1_END <= "0000111001"; -- 57 -- 141 -   1   57 + 84 missing = 141!!!
      VGA_SGI2_BGN <= "1011101101"; -- 749 -- 749 -  2  
      VGA_SSI2_BGN <= "1011110101"; -- 757 -  2  
      VGA_SSI2_END <= "1011111111"; -- 767 -   2  
	
	when others => null;

  end case;
end process;
--------------------------------------------------------------------------------
--   VGA:

process (DS80)                   
begin
  case DS80 is

    when '0' =>   -- ""
--		VGA_KSI_BGN  <= "0000001011"; --  11 -   
--		VGA_KSI_END  <= "0000001100"; --  12 -    
--		VGA_KGI1_END <= "0000101100"; --  44 -    
--		VGA_KGI2_BGN <= "1001110001"; -- 625 -   
		VGA_KSI_BGN  <= "0000010101"; --  21 -   
		VGA_KSI_END  <= "0000010110"; --  22 -    
		VGA_KGI1_END <= "0000100001"; --  33 -    
		VGA_KGI2_BGN <= "1010000000"; -- 640 -   

	when '1' =>   -- ""
		VGA_KSI_BGN  <= "0000001111"; --  15 -   
		VGA_KSI_END  <= "0000010000"; --  16 -    
--		VGA_KGI1_END <= "0000101100"; --  44 -    
		VGA_KGI1_END <= "0000001100"; --  12 -    
		VGA_KGI2_BGN <= "1001110001"; -- 625 -   
--		VGA_KSI_BGN  <= "0000110010"; --  50 -    -- 50 todo 42
--		VGA_KSI_END  <= "0000110011"; --  51 -     -- 51 todo 43
--		VGA_KGI1_END <= "0001100001"; --  97 -     -- 128 --
--		VGA_KGI2_BGN <= "1001000001"; -- 577 -    -- 624 --		
		--  480  ,   640480,        (  blank)
		
	when others => null;

  end case;
end process;
--------------------------------------------------------------------------------
--                      VGA              091223  --
--------------------------------------------------------------------------------
--     VIDEO
VGA_SSI  <= '0' when (VGA_H >= VGA_SSI1_BGN and VGA_H <= VGA_SSI1_END) 
                  or (VGA_H >= VGA_SSI2_BGN and VGA_H <= VGA_SSI2_END) 
                else '1';

--     VIDEO
VGA_SGI  <= '0' when (VGA_H <= VGA_SGI1_END)
                  or (VGA_H >= VGA_SGI2_BGN)
                else '1';

--------------------------------------------------------------------------------
--                      VGA              091223  --
--------------------------------------------------------------------------------
--    VIDEO
VGA_KSI  <= '0' when (VGA_V >= VGA_KSI_BGN) 
                 and (VGA_V <= VGA_KSI_END) 
                else '1';
--     VIDEO
VGA_KGI  <= '0' when (VGA_V <= VGA_KGI1_END) 
                  or (VGA_V >= VGA_KGI2_BGN )  
                else '1';
                  
--------------------------------------------------------------------------------
--                       VIDEO           091223  --
--------------------------------------------------------------------------------

--     VIDEO:

                       --   (14 )
--VIDEO_SSI1 <= '0' when (VIDEO_H > 20 and VIDEO_H < 87 and DS80 = '0')
--                       --  (12 )
--                    or (VIDEO_H > 17 and VIDEO_H < 75 and ds80 = '1')                
--                  else '1';

--   -   VIDEO:
                       --   (14 )
--VIDEO_SSI2 <= '0' when (VIDEO_H > 20 and VIDEO_H < 851 and DS80 = '0')
--                       --  (12 )
--                    or (VIDEO_H > 17 and VIDEO_H < 729 and DS80 = '1')                
--                  else '1';

--     VIDEO:
                       --   (14 )
--VIDEO_SGI  <= '0' when (VIDEO_H < 168 and DS80 = '0')
                       --  (12 )
--                    or (VIDEO_H < 144 and DS80 = '1')                
--                  else '1';

--------------------------------------------------------------------------------
--                      VIDEO            091103  --
--------------------------------------------------------------------------------
--    VIDEO
--VIDEO_KSI  <= '0' when VIDEO_V < 4 else '1';

--     VIDEO
--VIDEO_KGI  <= '0' when VIDEO_V < 16 else '1';


--------------------------------------------------------------------------------
--                       VIDEO              090820  --
--------------------------------------------------------------------------------
--VIDEO_SYNC <= VIDEO_SSI2 when VIDEO_KSI = '0' else VIDEO_SSI1;

--------------------------------------------------------------------------------
--                                   091025  --
--------------------------------------------------------------------------------
--    VIDEO
--VIDEO_BLANK <= VIDEO_KGI and VIDEO_SGI;

--------------------------------------------------------------------------------
--                     VIDEO                 										--
--------------------------------------------------------------------------------

LINEBUF: entity work.linebuf
port map (
	addra => VIDEO_V(0) & VIDEO_H(9 downto 0),
	clka 	 => CLK2,
	dina 	 => RGB,
	wea 	 => "1",
	
	addrb => (not VIDEO_V(0)) & VGA_H(8 downto 0) & VGA_H0,
	clkb 	 => VGA_RBGI_CLK,
	doutb  => RD_REG
);

process (VGA_RBGI_CLK)
begin 
	if (rising_edge(VGA_RBGI_CLK)) then 
		VGA_H0 <= not VGA_H0;
	end if;
end process;

--------------------------------------------------------------------------------
--      

process (CLK, VGA_KGI, VGA_SGI, VGA_KSI, VGA_SSI, EN) 
begin
if (rising_edge(CLK)) then  --    ,   0  1
      --    VGA
      VGA_BLANK   <= VGA_KGI and VGA_SGI;

		if (EN = '1') then 
			VSYNC_VGA <= VGA_KSI;      --    VGA
			HSYNC_VGA <= VGA_SSI;      --    VGA
		else 
			VSYNC_VGA <= KSI_IN;
			HSYNC_VGA <= SSI_IN xor (not KSI_IN);
		end if;
  end if;
end process;

--      
VGA_RBGI_CLK <= CLK2; 
      
--------------------------------------------------------------------------------
--                       RGBI   VGA                      091024  --
--------------------------------------------------------------------------------
process (VGA_RBGI_CLK, RD_REG, EN) 
begin
  if (rising_edge(VGA_RBGI_CLK)) then  --    ,
	 if (EN = '1') then
		 if (VGA_BLANK = '0') then 
			RGB_O <= (others => '0');
		 else 
			RGB_O <= RD_REG;
		 end if;
	 else 
		RGB_O <= RGB_IN;
	 end if;
  end if;
end process;

end RTL;
