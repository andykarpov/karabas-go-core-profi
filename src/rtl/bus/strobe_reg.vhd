-------------------------------------------------------------------------------
-- A register loaded at the end of a CPU strobe (M1_n, WR_n): Q takes D, if EN, as they were on the last clock edge
-- where STROBE_N was low, on the clock edge after STROBE_N went high.
--
-- It replaces flip-flops clocked by the strobe itself (clocks from logic, outside the timing analysis, with D and
-- EN racing the clock: EN of port #FE is decoded from IORQ_n, which goes high with WR_n). Q changes one clock
-- later than with the strobe as a clock. Checked against the old flip-flops by sim/tb_eq_strobes.vhd.
-------------------------------------------------------------------------------

library IEEE;
use IEEE.std_logic_1164.all;

entity strobe_reg is
generic (
	W				: integer := 8;
	INIT			: std_logic := '0'  -- every bit of Q after RESET and at power-on
);
port (
	CLK			: in std_logic;
	RESET			: in std_logic := '0';
	STROBE_N		: in std_logic;
	EN				: in std_logic := '1';
	D				: in std_logic_vector(W-1 downto 0);
	Q				: out std_logic_vector(W-1 downto 0)
);
end strobe_reg;

architecture rtl of strobe_reg is

signal strobe_r : std_logic := '1';
signal en_r : std_logic := '0';
signal d_r : std_logic_vector(W-1 downto 0) := (others => INIT);
signal q_r : std_logic_vector(W-1 downto 0) := (others => INIT);

begin

process (CLK)
begin
	if rising_edge(CLK) then
		strobe_r <= STROBE_N;
		if STROBE_N = '0' then
			en_r <= EN;
			d_r <= D;
		end if;
		if RESET = '1' then
			q_r <= (others => INIT);
		elsif STROBE_N = '1' and strobe_r = '0' and en_r = '1' then
			q_r <= d_r;
		end if;
	end if;
end process;

Q <= q_r;

end rtl;
