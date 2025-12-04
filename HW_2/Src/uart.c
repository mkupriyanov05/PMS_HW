#include "uart.h"
#include "stm32f103xb.h"
#include <stddef.h>
#include <stdint.h>


char RxBuffer[RX_BUFF_SIZE];			//Буфер приёма USART
char TxBuffer[TX_BUFF_SIZE];			//Буфер передачи USART
volatile bool ComReceived;				//Флаг приёма строки данных


/**
  * @brief  Инициализация USART2
  * @param  None
  * @retval None
  */
void initUSART2(void)
{
	RCC->APB2ENR |= RCC_APB2ENR_IOPAEN;
	RCC->APB2ENR |= RCC_APB2ENR_AFIOEN;						//включить тактирование альтернативных ф-ций портов
	RCC->APB1ENR |= RCC_APB1ENR_USART2EN;					//включить тактирование UART2

	GPIOA->CRL &= ~(GPIO_CRL_MODE2 | GPIO_CRL_CNF2);		//PA2 на выход
	GPIOA->CRL |= (GPIO_CRL_MODE2_1 | GPIO_CRL_CNF2_1);

	GPIOA->CRL &= ~(GPIO_CRL_MODE3 | GPIO_CRL_CNF3);		//PA3 - вход
	GPIOA->CRL |= GPIO_CRL_CNF3_0;

	/*****************************************
	Скорость передачи данных - 19200
	Частота шины APB1 - 32МГц

	1. USARTDIV = 32'000'000/(16*19200) = 104,1667
	2. 104 = 0x68
	3. 16*0.2 = 3
	4. Итого 0x683
	*****************************************/
	USART2->BRR = 0x683;

	USART2->CR1 |= USART_CR1_RE | USART_CR1_TE | USART_CR1_UE;
	USART2->CR1 |= USART_CR1_RXNEIE;						//разрешить прерывание по приему байта данных

	NVIC_EnableIRQ(USART2_IRQn);
}


/**
  * @brief  Обработчик прерывания от USART2
  * @param  None
  * @retval None
  */
void USART2_IRQHandler(void)
{
	if ((USART2->SR & USART_SR_RXNE)!=0)		//Прерывание по приёму данных
	{
		uint8_t pos = strlen(RxBuffer);			//Вычисляем позицию свободной ячейки

		RxBuffer[pos] = USART2->DR;				//Считываем содержимое регистра данных

		if ((RxBuffer[pos]== 0x0A) && (RxBuffer[pos-1]== 0x0D))							//Если это символ конца строки
		{
			ComReceived = true;					//- выставляем флаг приёма строки
			return;								//- и выходим
		}
	}
}

/**
  * @brief  Передача строки по USART2 без DMA
  * @param  *str - указатель на строку
  * @param  crlf - если true, перед отправкой добавить строке символы конца строки
  * @retval None
  */
void txStr(char *str, bool crlf)
{
	uint16_t i;

	if (crlf)												//если просят,
		strcat(str,"\r\n");									//добавляем символ конца строки

	for (i = 0; i < strlen(str); i++)
	{
		USART2->DR = str[i];								//передаём байт данных
		while ((USART2->SR & USART_SR_TC)==0) {};			//ждём окончания передачи
	}
}


void calc_LRC(uint8_t *data, size_t length) {
    uint8_t lrc = 0;
    for (size_t i = 0; i < length; i++) {
        lrc ^= (uint8_t)data[i];
    }
    snprintf(TxBuffer, TX_BUFF_SIZE, "LRC: %02X", lrc);
}


static int8_t hex_char_to_val(char c)
{
    if (c >= '0' && c <= '9') return c - '0';
    if (c >= 'A' && c <= 'F') return 10 + (c - 'A');
    if (c >= 'a' && c <= 'f') return 10 + (c - 'a');
    return -1;
}


void parse_hex(void) {
    size_t RxBuf_len = strlen(RxBuffer);
    bool RxBuf_len_is_odd = false;

    if (RxBuf_len % 2 != 0) {
        RxBuf_len_is_odd = true;
        RxBuf_len++;
        for (size_t i = RxBuf_len; i > 0; i--) {
            RxBuffer[i] = RxBuffer[i - 1];
        }
        RxBuffer[0] = '0';
    }

    size_t CharVals_len = RxBuf_len / 2;

    uint8_t CharVals[RX_BUFF_SIZE / 2 + 1] = {0};
    if (CharVals_len > (sizeof(CharVals) / sizeof(CharVals[0]))) {
        snprintf(TxBuffer, TX_BUFF_SIZE, "Error: Input too long");
        return;
    }

    int8_t hi = -1;
    int8_t lo = -1;

    int8_t i;
    for (i = 0; i < RxBuf_len; i = i + 2) {

        if (RxBuffer[i] == '\r' || RxBuffer[i] == '\n') {
            break;
        }
            
        hi = hex_char_to_val(RxBuffer[i]);
        lo = hex_char_to_val(RxBuffer[i + 1]);
        
        if (hi < 0) {
            if (RxBuf_len_is_odd == true) i--;
            snprintf(TxBuffer, TX_BUFF_SIZE, "Error: Invalid hex digit at pos %u",
                 (unsigned)(i));
            return;
        } 
        if (lo < 0) {
            if (RxBuf_len_is_odd == true) i--;
            snprintf(TxBuffer, TX_BUFF_SIZE, "Error: Invalid hex digit at pos %u",
                 (unsigned)(i + 1));
            return;
        }
        CharVals[i / 2] = ((hi << 4) | lo);
    }

    calc_LRC(CharVals, CharVals_len);			
}


void ExecuteCommand(void) {

    memset(TxBuffer, 0, TX_BUFF_SIZE);  // Очистка буфера передачи
    
    parse_hex();

    txStr(TxBuffer, true);
    memset(RxBuffer,0,RX_BUFF_SIZE);
	ComReceived = false;
}


bool COM_RECEIVED(void)
{
    return ComReceived;
}
