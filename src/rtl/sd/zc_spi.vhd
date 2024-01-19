library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;

entity zc_spi is
port(
	CLK	  : in std_logic;
	ENA  	  : in std_logic;
	RESET   : in std_logic;
	
	DI      : in std_logic_vector(7 downto 0);
	START   : in std_logic;
	MISO    : in std_logic;
	WR_EN   : in std_logic;

	DO      : out std_logic_vector(7 downto 0);
	SCK     : buffer std_logic;
	MOSI    : out std_logic;
	BUSY 	  : out std_logic
);
end;

architecture spi_rtl of zc_spi is

signal counter      : unsigned(3 downto 0) := "1111";
signal shift_reg    : std_logic_vector(8 downto 0) := "111111111"; -- extra bit because we write on the falling edge and read on the rising edge
signal in_reg       : std_logic_vector(7 downto 0) := "11111111";

begin

	SCK				 <= counter(0);
	MOSI            <= shift_reg(8);
	DO 				 <= in_reg;

	process (CLK)
	begin 
		if rising_edge(CLK) then
			if RESET = '1' then 
				shift_reg <= (others => '1');
				in_reg <= (others => '1');
				counter <= "1111"; -- Idle
				busy <= '0';
			else
				if counter = "1111" then 
					in_reg <= shift_reg(7 downto 0);
					busy <= '0';
					if start = '1' then 
						if WR_EN = '0' then 
							shift_reg <= (others => '1');
						else
							shift_reg <= DI & '1';
						end if;
						counter <= "0000";
						busy <= '1';
					end if;
				else
					if ENA = '1' then
						if counter = "1000" then
							busy <= '0';
						end if;
						counter <= counter + 1;
						if (counter(0) = '0') then 
							shift_reg(0) <= MISO;
						else 
							shift_reg <= shift_reg(7 downto 0) & '1';
						end if;
					end if;
				end if;
			end if;
		end if;
	end process;

end spi_rtl;