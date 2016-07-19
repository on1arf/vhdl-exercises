
/*
 * test FPGA code: uart_send
 * set 8 bit value on parallel port , set "start_uart" pin
 *         -> check UART RX if correct and it "buffer_empty" pin correcty set
 */


#define BYTE_TO_BINARY_PATTERN "%c%c%c%c%c%c%c%c"
#define BYTE_TO_BINARY(byte)  \
  (byte & 0x80 ? '1' : '0'), \
  (byte & 0x40 ? '1' : '0'), \
  (byte & 0x20 ? '1' : '0'), \
  (byte & 0x10 ? '1' : '0'), \
  (byte & 0x08 ? '1' : '0'), \
  (byte & 0x04 ? '1' : '0'), \
  (byte & 0x02 ? '1' : '0'), \
  (byte & 0x01 ? '1' : '0') 

// PINs:
//		PA[0-7]: parallel port to fpga
// 	PB10-PB11: USART3: communication with fpga
//		PC13: "start_send" to fpga
//		PC14: "uart buffer empty" from fpga

//		PA[9-10]: UART1: communication with host

// some generic defines
#define FOREVER 1

#define TIMEOUT 1000
#define REPEAT 2


// F_UART_BUS: FPGA UART 8 bit bus (PA[0-7])
#define GPIO_F_UART_BUS GPIOA
#define GPIO_F_UART_BUSp GPIO0|GPIO1|GPIO2|GPIO3|GPIO4|GPIO5|GPIO6|GPIO7

// F_UART_TXSEND: FPGA "start send" pin (PC13): OUTPUT
#define GPIO_F_UART_TXSEND GPIOC
#define GPIO_F_UART_TXSENDp GPIO13

// F_UART_TXBE: FPGA "buffer empty" pin (PC14): INPUT
#define GPIO_F_UART_TXBE GPIOC
#define GPIO_F_UART_TXBEp GPIO14



// LED
// GPIOB, GPIO1
#define GPIO_LED GPIOB
#define GPIO_LEDp GPIO1

// USART1:
// GPIOA, GPIO10: RX
// GPIOA, GPIO9: TX
#define GPIO_USART1 GPIOA

// USART3:
// GPIOB, GPIO11: RX
// GPIOB, GPIO10: TX
#define GPIO_USART3 GPIOB



#include <libopencm3/stm32/rcc.h>
#include <libopencm3/stm32/gpio.h>
#include <libopencm3/stm32/usart.h>
#include <stdio.h>
#include <errno.h>

#include <libopencm3/cm3/nvic.h>
#include <libopencm3/cm3/systick.h>
#include <libopencm3/cm3/scb.h>

#include "string.h"


// global data

/* monotonically increasing number of milliseconds from reset
 * overflows every 49 days if you're wondering
 */
volatile uint32_t system_millis=0;

/* sleep for delay milliseconds */
static void wait_ms(uint32_t delay)
{
        uint32_t wake = system_millis + delay;
        while (wake > system_millis);
}

/* Called when systick fires */
void sys_tick_handler(void)
{
        system_millis++;
}

/* Set up a timer to create 1mS ticks. */
static void systick_setup(void)
{
        /* clock rate / 1000 to get 1mS interrupt rate */
        systick_set_reload(3000); // 24 Mhz / 8 = 3000
        systick_set_clocksource(STK_CSR_CLKSOURCE_AHB_DIV8);
        systick_counter_enable();
        /* this done last */
        systick_interrupt_enable();
}


static void clock_setup(void)
{
        rcc_clock_setup_in_hse_8mhz_out_24mhz();

        /* Enable GPIOA, GPIOB, GPIOC clock. */
        rcc_periph_clock_enable(RCC_GPIOA);
        rcc_periph_clock_enable(RCC_GPIOB);
        rcc_periph_clock_enable(RCC_GPIOC);

        /* Enable clocks for GPIO port A (USART1) and Port B (USART3) */
        rcc_periph_clock_enable(RCC_GPIOA);
        rcc_periph_clock_enable(RCC_GPIOB);
        rcc_periph_clock_enable(RCC_AFIO);
        rcc_periph_clock_enable(RCC_USART1);
        rcc_periph_clock_enable(RCC_USART3);

}

static void usart_setup(void)
{
// GPIO_USART1: used to communicate with host

/* Setup GPIO pin GPIO_USART1_TX and GPIO_USART1_RX. */
gpio_set_mode(GPIO_USART1, GPIO_MODE_OUTPUT_50_MHZ, GPIO_CNF_OUTPUT_ALTFN_PUSHPULL, GPIO_USART1_TX);
gpio_set_mode(GPIO_USART1, GPIO_MODE_INPUT, GPIO_CNF_INPUT_FLOAT, GPIO_USART1_RX);

/* Setup UART parameters. */
usart_set_baudrate(USART1, 38400);
usart_set_databits(USART1, 8);
usart_set_stopbits(USART1, USART_STOPBITS_1);
usart_set_mode(USART1, USART_MODE_TX_RX);
usart_set_parity(USART1, USART_PARITY_NONE);
usart_set_flow_control(USART1, USART_FLOWCONTROL_NONE);

/* Finally enable the USART. */
usart_enable(USART1);


// GPIO_USART3: used to communicate with fpga

/* Setup GPIO pin GPIO_USART3_TX and GPIO_USART3_RX. */
gpio_set_mode(GPIO_USART3, GPIO_MODE_OUTPUT_50_MHZ, GPIO_CNF_OUTPUT_ALTFN_PUSHPULL, GPIO_USART3_TX);
gpio_set_mode(GPIO_USART3, GPIO_MODE_INPUT, GPIO_CNF_INPUT_FLOAT, GPIO_USART3_RX);

/* Setup UART parameters. */
usart_set_baudrate(USART3, 9600);
usart_set_databits(USART3, 8);
usart_set_stopbits(USART3, USART_STOPBITS_1);
usart_set_mode(USART3, USART_MODE_TX_RX);
usart_set_parity(USART3, USART_PARITY_NONE);
usart_set_flow_control(USART3, USART_FLOWCONTROL_NONE);

/* Enable the USART. */
usart_enable(USART3);



}

void write_uart1(char *ptr, int len)
{
int i;

for (i = 0; i < len; i++)
        usart_send_blocking(USART1, ptr[i]);

}

static void gpio_setup(void)
{
/// Set GPIO1 (in GPIO port B) to 'output push-pull' for LED
gpio_set_mode(GPIO_LED, GPIO_MODE_OUTPUT_2_MHZ, GPIO_CNF_OUTPUT_PUSHPULL, GPIO_LEDp);

// Set pins 0 up to 7 of port A for output "UART bus"
gpio_set_mode(GPIO_F_UART_BUS, GPIO_MODE_OUTPUT_2_MHZ, GPIO_CNF_OUTPUT_PUSHPULL, GPIO_F_UART_BUSp);

// Set pin PC13  for output "UART start_send"
gpio_set_mode(GPIO_F_UART_TXSEND, GPIO_MODE_OUTPUT_2_MHZ, GPIO_CNF_OUTPUT_PUSHPULL, GPIO_F_UART_TXSENDp);

// Set pin PC14  for input "UART buffer_empty"
// enable pull down
gpio_set_mode(GPIO_F_UART_TXBE, GPIO_MODE_INPUT, GPIO_CNF_INPUT_PULL_UPDOWN, GPIO_F_UART_TXBEp);
gpio_clear(GPIO_F_UART_TXBE,  GPIO_F_UART_TXBEp);

}



int main(void) {
char printtxt[80];

clock_setup();
gpio_setup();
usart_setup();
systick_setup();

snprintf(printtxt,80,"FPGA UART_SEND tester ready ... go go go !\r\n");
write_uart1(printtxt,strlen(printtxt));


// blink LED 4 times

for (int l=0; l<4;l++) {
	gpio_set(GPIO_LED,GPIO_LEDp);
	wait_ms(500);					
	gpio_clear(GPIO_LED,GPIO_LEDp);
	wait_ms(500);					
}; // end for 


while(FOREVER) {
	int c; // character to send
	uint16_t ret;
	int success;
	uint32_t sendStartTime;

	int c2;


	for (c=0; c<=0xff; c++) {
		for (c2=0; c2<REPEAT; c2++) {
			// Make data
			snprintf(printtxt,80,"setting %02X on the bus! ",c);
			write_uart1(printtxt,strlen(printtxt));

			snprintf(printtxt,80,"bin: "BYTE_TO_BINARY_PATTERN"\n", BYTE_TO_BINARY(c));
			write_uart1(printtxt,strlen(printtxt));

			gpio_port_write(GPIOA,(c & 0xFF));


			// toggle "uart_start_TX" pin high and low
			gpio_set(GPIO_F_UART_TXSEND,GPIO_F_UART_TXSENDp);
			wait_ms(1);					
			gpio_clear(GPIO_F_UART_TXSEND,GPIO_F_UART_TXSENDp);
			wait_ms(1);					


			// wait up to 1 second to receive data from uart
			sendStartTime = system_millis;

			while(1) {
				success = usart_get_flag(USART3,USART_SR_RXNE);
				if (success) {
					// Got data
					ret=(usart_recv(USART3) & 0xff);
					break;
				}; // end if

				if (system_millis - sendStartTime > TIMEOUT) {
					// Timeout
					break;
				}; // end if
			}; // end while

			if (success) {
				if (ret == (c & 0xFF)) {
					snprintf(printtxt,80,"Received: OK\n");
				} else {
					snprintf(printtxt,80,"Received: "BYTE_TO_BINARY_PATTERN"\n", BYTE_TO_BINARY(ret));
				}; // end else - if

				write_uart1(printtxt,strlen(printtxt));
				wait_ms(10);					
			} else {
				snprintf(printtxt,80,"No data received from Serial USART3\n");
				write_uart1(printtxt,strlen(printtxt));
			}; // end else - if

		}; // end for c2

	}; // end for

}; // end while (forever)

return(0);

} // END MAIN



