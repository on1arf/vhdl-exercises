library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-- notice how the use of these libraries was avoided
-- use ieee.std_logic_arith.all ;
-- use ieee.std_logic_unsigned.all;

-- entity
entity uart_send is
port (	enable		:	in std_logic;
	clk		:	in std_logic;
	uart_start	:	in std_logic;
	uart_in		:	in std_logic_vector (7 downto 0);
	uart_tx		:	out std_logic;
	uart_tx2		:	out std_logic;
	uart_txbe	:	out std_logic -- tx buffer empty 
     );

end uart_send;



architecture a_uart_send of uart_send is

-- used in process statemachine
type t_state is (IDLE,TX);
signal state : t_state := IDLE; -- init state to IDLE

signal bitcount : integer range 0 to 10 := 0;
signal txbuffer : std_logic_vector (9 downto 0);


-- used by process clockdivider
signal s_clock_9k6 : std_logic := '0';
signal clkdivcount : integer range 0 to 5207 := 0; -- 50 Mhz / 5208 = 9600 bps

-- used by process startdetect
signal s_startdetect : std_logic := '0';
signal start_last : std_logic := '1';	-- init as "1" to avoid false positive at startup

-- latches
signal l_uart_tx : std_logic;
signal l_uart_txbe : std_logic; 

begin

--- STATE MACHINE
p_statemachine: process (clk,s_startdetect,s_clock_9k6,uart_in,enable) is
begin

-- everything is clocked
if (rising_edge(clk)) then
	-- enable pin overrides all
	if (enable = '0') then
		-- not enabled -> set all output in tristate
		l_uart_tx <= 'Z';
		l_uart_txbe <= 'Z';

		state <= IDLE;  
	else
		-- state machine
		case (state) is 
		when IDLE =>
		-- state IDLE
		-- move from IDLE to TX_WAIT as soon as possible, so not clocked to 9k6 clock

			-- init uart tx and tx buffer empty
			l_uart_txbe <= '1';
			l_uart_tx <= '1';

			if (s_startdetect = '1') then
			-- start detected: copy input to buffer, Do not output anything yet, wait for next 9600 clock
				txbuffer <= '1' & uart_in & '0'; -- store data in txbuffer
				l_uart_txbe <= '0';
				bitcount <= 0;
				state <= TX;
			end if; -- startdetect
		when TX => 
		-- state TX
		-- clocked by 9600 clock
			if (s_clock_9k6 = '1') then
			
				-- move back to idle state with last bit has been send
				-- else output tx data
				if (bitcount >= 9) then
					state <= IDLE;
				else
					l_uart_tx <= txbuffer(bitcount);
					bitcount <= bitcount + 1;				
				end if;

			end if; -- 9k6 clock

		when others =>
			-- we should never get here.
			state <= IDLE;
		end case;

	end if;  -- enable / not enabled

end if; -- rising edge cllk

end process p_statemachine;



-- copy latch to output port
uart_tx <= l_uart_tx;
uart_tx2 <= not l_uart_tx;
uart_txbe <= l_uart_txbe;


---- DETECT START
---- Positive edge detector
p_detectstart: process (clk, uart_start)
begin

if (rising_edge(clk)) then
	if ((uart_start = '1') and (start_last = '0')) then
		s_startdetect <= '1';
	else
		s_startdetect <= '0';
	end if; -- detect start

	start_last <= uart_start;
end if; -- risiing_edge

end process p_detectstart;


---- CLOCK DIVIDER
---- generate 9600 Hz clock from 50 Mhz
p_clockdivider: process (clk)
begin

if (rising_edge(clk)) then
	if (clkdivcount = 5207) then
		clkdivcount <= 0;
		s_clock_9k6 <= '1';
	else
		clkdivcount <= clkdivcount + 1;
		s_clock_9k6 <= '0';
	end if;
end if; -- rising_edge

end process p_clockdivider;


end a_uart_send; -- end architecture