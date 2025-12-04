#ifndef UART_H_
#define UART_H_

#include "stm32f1xx.h"
#include <stdbool.h>
#include <string.h>
#include <stdio.h>

#define	RX_BUFF_SIZE	256
#define TX_BUFF_SIZE	256

void USART2_IRQHandler(void);
void initUSART2(void);
void parse_hex(void);
void txStr(char *str, bool crlf);
void ExecuteCommand(void);
bool COM_RECEIVED(void);

#endif