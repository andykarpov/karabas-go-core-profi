-- The flip-flops strobe_reg replaced (profi.vhd before it): clocked by the strobe itself.
--   fd_port:       process (fd_sel, reset, cpu_m1_n) ... if reset = '1' then fd_port <= '1';
--                  elsif rising_edge(cpu_m1_n) then fd_port <= fd_sel;
--   port_xxfe_reg: port_xxfe_reg <= cpu_do_bus when cs_xxfe = '1' and (cpu_wr_n'event and cpu_wr_n = '1');

library IEEE;
use IEEE.std_logic_1164.all;

entity strobe_reg_ref is
generic (
	W				: integer := 8;
	INIT			: std_logic := '0'
);
port (
	RESET			: in std_logic := '0';
	STROBE_N		: in std_logic;
	EN				: in std_logic := '1';
	D				: in std_logic_vector(W-1 downto 0);
	Q				: out std_logic_vector(W-1 downto 0)
);
end strobe_reg_ref;

architecture rtl of strobe_reg_ref is
signal q_r : std_logic_vector(W-1 downto 0) := (others => INIT);
begin
process (RESET, STROBE_N)
begin
	if RESET = '1' then
		q_r <= (others => INIT);
	elsif rising_edge(STROBE_N) then
		if EN = '1' then
			q_r <= D;
		end if;
	end if;
end process;
Q <= q_r;
end rtl;
