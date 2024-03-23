-------------------------------------------------------------------------------
-- USB HID mouse to serial MS mouse transformer
-------------------------------------------------------------------------------

library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.std_logic_arith.conv_integer;
use IEEE.numeric_std.all;
use IEEE.std_logic_unsigned.all;

entity serial_mouse_convertor is
	port
	(
	 CLK			 : in std_logic;
	 RESET 		 : in std_logic;
	 
	 -- incoming usb mouse events
	 MS_X    : in std_logic_vector(7 downto 0);
	 MS_Y    : in std_logic_vector(7 downto 0);
	 MS_B    : in std_logic_vector(2 downto 0);
	 MS_UPD  : in std_logic;
	 
	 -- serial mouse uart
	 MOUSE_TX : out std_logic;
	 MOUSE_RTS : in std_logic
	 
	);
end serial_mouse_convertor;

architecture rtl of serial_mouse_convertor is

	type qmachine IS(idle, send_m, send_byte1, send_byte2, send_byte3);
	signal qstate : qmachine := idle;
	
	type smachine IS(serial_idle, send_byte, serial_tx, serial_end);
	signal sstate : smachine := serial_idle;
	
	signal acc_x : signed(7 downto 0) := 0;
	signal acc_y : signed(7 downto 0) := 0;
	signal acc_b : std_logic_vector(2 downto 0) := "000";
	signal prev_ms_upd : std_logic := '0';
	signal prev_b : std_logic_vector(2 downto 0);

	signal rtsbuf : std_logic_vector(3 downto 0) := "0000";
	signal mousebuf_x : std_logic_vector(7 downto 0) := "00000000";
	signal mousebuf_y : std_logic_vector(7 downto 0) := "00000000";
	signal mousebuf_b : std_logic_vector(2 downto 0) := "000";
	signal serialbuf : std_logic_vector(9 downto 0) := (others => '1'); -- stop, data, start

	signal cnt : std_logic_vector(15 downto 0) := (others => '0'); -- serial prescaler counter
	signal prescaler: std_logic_vector(15 downto 0) := "0101000101100000"; -- serial prescaler = 50000000 / 1200 / 2 - 1 = 20832
	signal bitcnt : std_logic_vector(4 downto 0) := (others => '0');
	
begin 

	process (CLK) 
	begin
		if rising_edge(CLK) then
			
			-- load rts buffer
			rtsbuf <= rtsbuf(2 downto 0) & MOUSE_RTS;
			
			-- prescaler counter
			if (cnt == prescaler) then 
				cnt <= 0;
			else
				cnt <= cnt + 1;
			end if;
			
			-- accumulate usb hid data into acc_x, acc_y, acc_b
			if ms_upd /= prev_ms_upd then 
				acc_x <= acc_x + signed(ms_x);
				acc_y <= acc_y - signed(ms_y);
				acc_b <= ms_b;
				prev_ms_upd <= ms_upd;
			end if;
			
			-- mouse fsm
			case qstate is 
			
				when idle => 				
					if rtsbuf == "0011" then 
						qstate <= send_m;
					elsif (acc_x /= 0 or acc_y /= 0 or acc_b /= prev_b then 
						mousebuf_x <= acc_x;
						mousebuf_y <= acc_y;
						mousebuf_b <= acc_b;					
						acc_x <= 0;
						acc_y <= 0;
						prev_b <= acc_b;
						qstate <= send_byte1;
					end if;
					
				when send_m => 
					if (sstate == serial_idle) then 
						serialbuf <= '1' & x"4D" & '0';
						sstate <= send_byte;
					elsif (sstate == serial_end) then 
						sstate <= serial_idle;
						qstate <= idle;
					end if;
					
				when send_byte1 => 
					if (sstate == serial_idle) then
						serialbuf <= '1' & "11" & mousebuf_b[0] & mousebuf_b[1] & mousebuf_y(7 downto 6) & mousebuf_x(7 downto 6) & '0';
						sstate <= send_byte;
					elsif (sstate == serial_end) then 
						sstate <= serial_idle;
						qstate <= send_byte2;
					end if;
					
				when send_byte2 => 
					if (sstate == serial_idle) then
						serialbuf <= '1' & "10" & mousebuf_x(5 downto 0) & '0';
						sstate <= send_byte;
					elsif (sstate == serial_end) then 
						sstate <= serial_idle;
						qstate <= send_byte3;
					end if;

				when send_byte3 => 
					if (sstate == serial_idle) then
						serialbuf <= '1' & "10" & mousebuf_y(5 downto 0) & '0';
						sstate <= send_byte;
					elsif (sstate == serial_end) then 
						sstate <= serial_idle;
						qstate <= idle;
					end if;					
			end case;
			
			-- uart tx fsm
			case sstate => 

				when serial_idle => null;

				when send_byte => 
					bitcnt <= 9;
					sstate <= serial_tx;					

				when serial_tx => 
					if cnt == 0 then
						if (bitcnt > 0) then 
							bitcnt <= bitcnt - 1;
							serialbuf <= '1' & serialbuf(8 downto 1);
							mouse_tx <= serialbuf(0);
						else 
							sstate <= serial_end;
							mouse_tx <= '1';
						end if;
					end if;
				
				when serial_end => 
					sstate <= serial_idle;
			
		end if;
	end process;

end rtl;