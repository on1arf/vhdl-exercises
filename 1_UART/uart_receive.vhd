library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-- entity
entity uart_receive is
port (	enable		:	in std_logic;
	clk		:	in std_logic;
	uart_rx		:	in std_logic;
	uart_readdata	:	in std_logic;

	uart_tx		:	out std_logic_vector (7 downto 0);
	uart_txda	:	out std_logic; -- tx data available 
	uart_txov	:	out std_logic; -- tx buffer overflow detected
	uart_rxerror	:	out std_logic; -- rx receive error

	led_txda		:	out std_logic;
	led_txov		:	out std_logic;
	led_rxerror	:	out std_logic 

	);

end uart_receive;



architecture a_uart_receive of uart_receive is

-- used in process statemachine
type t_state is (IDLE,START,RX);
signal state : t_state := IDLE; -- init state to IDLE

signal bitcount : integer range 0 to 10 := 0;

signal rxbuffer : std_logic_vector (7 downto 0);

-- used by process clockdivider
signal s_clock9k6_halfway : std_logic := '0';
signal clkdivcount : integer range 0 to 5207 := 0; -- 50 Mhz / 5208 = 9600 bps

-- clock reset
signal s_clkreset : std_logic;
signal s_clkreset_edgeup : std_logic;
signal last_clkreset : std_logic;


-- "buffer-fill" signal: created by state machine, triggers p_output_buffer
signal s_bufffill : std_logic := '0';
signal s_bufffill_edgeup : std_logic := '0';
signal last_s_bufffill : std_logic := '1';	-- init as "1" to avoid false positive at startup


-- edge detection readdata signal
signal s_readdata_edgeup : std_logic;
signal last_readdata : std_logic;



-- edge detection signals UART_RX input put
signal s_uartrx_edgedown : std_logic;
signal last_uartrx : std_logic;

-- latches
signal l_uart_tx : std_logic_vector (7 downto 0);
signal l_uart_txda : std_logic; 
signal l_uart_txov : std_logic;
signal l_uart_rxerror : std_logic;


begin

--- STATE MACHINE
p_statemachine: process (clk,s_clock9k6_halfway,uart_rx,enable)
begin

-- everything is clocked
if (rising_edge(clk)) then
	-- enable pin overrides all
	if (enable = '0') then
		-- not enabled -> set all output in tristate
		-- > the statemachine controls one output pin: 
		l_uart_rxerror <= 'Z';

		state <= IDLE;  
	else
		-- state machine
		case (state) is 
		when IDLE =>
		-- state IDLE
		-- move from IDLE to TX_WAIT as fast as possible, so not clocked to 9k6 clock


			-- clear "buffer fill" flag: was set when moving from successfull receive (state RX) back to IDLE
			s_bufffill <= '0';


			-- move from IDLE to TX at falling edge of UART_RX
			-- then reset 9k6 counter
			if (s_uartrx_edgedown = '1') then
				s_clkreset <= '1';
				state <= START;

				-- clear rxerror
				l_uart_rxerror <= '0';
			end if;

		when START =>

			-- done always 
			s_clkreset <= '0'; -- clear "s_clkreset" when moving from IDLE to START

			-- clocked by 9600 clock
			if (s_clock9k6_halfway = '1') then


				-- halfway the startbit we should have a low
				if (uart_rx = '0') then
					bitcount <= 0;
					state <= RX;
				else
				-- error: return to IDLE state
					l_uart_rxerror <= '1';
					state <= IDLE;
				end if;
			end if; -- halfway 9k6 clock


		when RX => 
		-- state RX

			-- clocked by 9600 clock
			if (s_clock9k6_halfway = '1') then

				if ((bitcount >= 0) and (bitcount < 9)) then
				-- bits 1 to 8: store them
					rxbuffer(bitcount) <= uart_rx;
					bitcount <= bitcount + 1;

				elsif (bitcount = 9) then
				-- halfway bit 9 (stopbit) we should have a high
					if (uart_rx = '1') then
						-- data is good, set "fillbuffer" flag to store it in buffer
						s_bufffill <= '1';
					else
					-- error: set "error" pin
						l_uart_rxerror <= '1';
					end if;

					-- in both cases, go back to IDLE state
					state <= IDLE;

				else 
				-- we should never get here.
					state <= IDLE;
				end if;

			end if; -- 9k6 clock

		when others =>
			-- we should never get here.
			state <= IDLE;
		end case;

	end if;  -- enable / not enabled

end if; -- rising edge cllk

end process p_statemachine;



-------------------------- process "output buffer" ----------------

-- the buffer contains 8 bits
-- data is loaded into buffer with "s_bufffill_edgeup" signal
-- when data is loaded into buffer, s_uart_txda (data availableà signal is set

-- data is concidered to be read (by the host) if a "s_readdata" signal is set high

-- if data could not be loaded (tx overrun), the "tx_overrun" signal is set and new data is not loaded in buffer

p_output_buffer: process (clk,s_readdata_edgeup, s_bufffill_edgeup)
begin

if (rising_edge(clk)) then

	-- enable pin overrides all
	if (enable = '0') then
		-- not enabled -> set all output in tristate

		-- > the p_output_buffer controls our output pin (txda and txov) and the 8bit output buffer 
		l_uart_txda <= 'Z';
		l_uart_txov <= 'Z';

		l_uart_tx <= "ZZZZZZZZ";

	else 
		-- load data in buffer on rising edge of s_bufffill 
		if (s_bufffill_edgeup = '1') then

			-- is there place in the buffer?
			if (l_uart_txda = '0') then
			-- yes, output data
				l_uart_tx <= rxbuffer;
				l_uart_txda <= '1';
				l_uart_txov <= '0';
			else
			-- nope, set "overrun" bit but do not change data in output buffer
				l_uart_txov <= '1';
			end if; -- place in buffer ?
		end if; -- loading data in buffer


	end if;

	-- reading data from buffer, set data as "read" when "readdata" goes low only and when data is available in buffer (data available = 1)
	if ((s_readdata_edgeup = '1') and (l_uart_txda = '1')) then
		l_uart_txda <= '0';
		l_uart_txov <= '0';
	end if;


end if; -- rising_edge

end process p_output_buffer;



--------------------- OUTPUT LEDGES ---------------

-- copy letched to output pins
uart_txda <= l_uart_txda;
uart_txov <= l_uart_txov;
uart_tx <= l_uart_tx;
uart_rxerror <= l_uart_rxerror;


led_txda <= not l_uart_txda;
led_txov <= not l_uart_txov;
led_rxerror <= not l_uart_rxerror;


---------------------- EDGE DETECTORS -------------

---- buffer_fill signal
---- positive edge detector
p_bufffill_edgeup: process (clk, s_bufffill)
begin

if (rising_edge(clk)) then
	if ((s_bufffill = '1') and (last_s_bufffill = '0')) then
		s_bufffill_edgeup <= '1';
	else
		s_bufffill_edgeup <= '0';
	end if; -- detect start

	last_s_bufffill <= s_bufffill;
end if; -- risiing_edge

end process p_bufffill_edgeup;




---- DETECT UART_RX start
---- Negative edge detector
p_uartrx_edgedown: process (clk, uart_rx)
begin

if (rising_edge(clk)) then
	if ((uart_rx = '1') and (last_uartrx = '1')) then
		s_uartrx_edgedown <= '1';
	else
		s_uartrx_edgedown <= '0';
	end if; -- detect start

	last_uartrx <= uart_rx;
end if; -- risiing_edge

end process p_uartrx_edgedown;



---- DETECT BUFREAD line
---- Positive edge detector
p_readdata_edgeup: process (clk, uart_readdata)
begin

if (rising_edge(clk)) then
	if ((uart_readdata = '1') and (last_readdata = '0')) then
		s_readdata_edgeup <= '1';
	else
		s_readdata_edgeup <= '0';
	end if; -- detect start

	last_readdata <= uart_readdata;
end if; -- risiing_edge

end process p_readdata_edgeup;


---- DETECT CLOCK RESET
---- Positive edge detector
p_clkreset_edgeup: process (clk, s_clkreset)
begin

if (rising_edge(clk)) then
	if ((s_clkreset = '1') and (last_clkreset = '0')) then
		s_clkreset_edgeup <= '1';
	else
		s_clkreset_edgeup <= '0';
	end if; -- detect start

	last_clkreset <= s_clkreset;
end if; -- risiing_edge

end process p_clkreset_edgeup;



---- CLOCK DIVIDER
---- generate 9600 Hz clock from 12 Mhz
p_clockdivider: process (clk,s_clkreset_edgeup)
begin

if (rising_edge(clk)) then
	if (s_clkreset_edgeup = '1') then
		clkdivcount <= 0;
		s_clock9k6_halfway <= '0';
	else
		if (clkdivcount = 2604) then
			clkdivcount <= clkdivcount + 1;

			s_clock9k6_halfway <= '1';

		elsif (clkdivcount = 5207) then
			clkdivcount <= 0;

			s_clock9k6_halfway <= '0';

		else
			clkdivcount <= clkdivcount + 1;

			s_clock9k6_halfway <= '0';
		end if;
	end if; -- rising
end if; -- rising_edge

end process p_clockdivider;

end a_uart_receive; -- end architecture
