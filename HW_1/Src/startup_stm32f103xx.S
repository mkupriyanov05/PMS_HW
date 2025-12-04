/**
 ******************************************************************************
 * @brief     STM32F103xx device vector table for GCC toolchain.
 *            This module performs:
 *                - Set the initial SP
 *                - Set the initial PC == Reset_Handler,
 *                - Set the vector table entries with the exceptions ISR address
 *                - Branches to main in the C library (which eventually
 *                  calls main()).
 ******************************************************************************
 * @attention
 *
 * Copyright (c) 2025 STMicroelectronics.
 * All rights reserved.
 *
 * This software is licensed under terms that can be found in the LICENSE file
 * in the root directory of this software component.
 * If no LICENSE file comes with this software, it is provided AS-IS.
 *
 ******************************************************************************
 */

.syntax unified
.cpu cortex-m3
.fpu softvfp
.thumb

.include "stm32f10x.s"

.global g_pfnVectors
.global Default_Handler

/* start address for the initialization values of the .data section.
defined in linker script */
.word _sidata
/* start address for the .data section. defined in linker script */
.word _sdata
/* end address for the .data section. defined in linker script */
.word _edata
/* start address for the .bss section. defined in linker script */
.word _sbss
/* end address for the .bss section. defined in linker script */
.word _ebss

/**
 * @brief  This is the code that gets called when the processor first
 *          starts execution following a reset event. Only the absolutely
 *          necessary set is performed, after which the application
 *          supplied main() routine is called.
 * @param  None
 * @retval : None
*/


  .section .text.Reset_Handler
  .weak Reset_Handler
  .type Reset_Handler, %function
Reset_Handler:
	ldr		r0, =_estack
	mov		sp, r0          /* set stack pointer */

	ldr		r0, =PERIPH_BB_BASE+ \
				(RCC_APB2ENR-PERIPH_BASE)*32 + \
				4*4						// bitbanding найти адрес бита для тактирования порта С
	mov		r1, #1						// запись "1" в регистр r1 для загрузки в r0
	str 	r1, [r0]					// загрузка значения из r1 в r0 для разрешения тактирования

    ldr		r0, =GPIOC_CRL				// запись адреса нижнего конфиг регистра порта С в r0
	ldr		r1, =0x03					// запись маски в r1: для PC0 - 00 11 (output 50MHz, general push-pull)
	ldr		r2, [r0]					// считывание порта	в r2
    bfi		r2, r1, #0, #4				// копирование битов маски в позицию PIN0
    str		r2, [r0]					// загрузка результата в конфиг регистр порта

	ldr		r10, =0x20000100			// базовый адрес регистров в памяти
	ldr		r0, =0x3A7F1E4D				// 0011 1010 0111 1111 0001 1110 0100 1101
	str		r0, [r10]					// запись тестовых данных (верхнего) в память

	ldr		r0, =0xE2B45A0F				// 1110 0010 1011 0100 0101 1010 0000 1111
	str		r0, [r10, #4]				// запись тестовых данных (нижнего) в память (сдвиг 4 байта)

	// ожидаемый вывод: 0100 1111 0110 1011 1000 0110 1100 0011 (0x4f6b86c3)


/*
Регистры:
- r0 - данные верхнего регистра
- r1 - данные нижнего регистра
- r3 - выходные данные
*/
loop:
	mov		r3, #0						// обнуление регистра для выходных данных

	// Получение адресов нижнего и верхнего 32-б регистров (r0, r1)
	ldr		r0, [r10]					// чтение верхнего
	ldr		r1, [r10, #4]				// чтение нижнего (сдвиг на 4 байта)
	
	bl		choosing_high				// подпрограмма для заполнения верхней половины
	lsl		r3, r3, #1					// сдвиг для перехода к заполнению нижней половины
	bl		choosing_low				// подпрограмма для заполнения нижней половины

	bl		output						// подпрограмма для послед вывода данных на PC0

	bl		delay						// задержка перед новой итерацией
	bl		delay
	bl		delay
	bl		delay
	bl		delay

	b		loop

/*
Регистры:
- r0 - данные верхнего регистра (glob)
- r1 - данные нижнего регистра (glob)
- r3 - выходные данные (glob)
- r4 - счетчик битов (15 - 0)
- r5 - служебный регистр для изменения данных
- r8 - служебный регистр для правильного копирования бита
*/
choosing_high:
	push	{r4, r5, r8}				// запись local регистров в стек
	mov		r4, #15						// обнуление счетчика битов в регистрах
	mov		r5, r0						// копирование r0 в r5 для изменения
	lsl		r5, r5, #1					// изначальный сдвиг для работы с четным битом
	b		choosing_loop				// переход к циклу выбора

choosing_low:
	push	{r4, r5, r8}				// запись local регистров в стек
	mov		r4, #15						// обнуление счетчика битов в регистрах
	mov		r5, r1						// копирование r0 в r5 для изменения
	lsl		r5, r5, #1					// изначальный сдвиг для работы с четным битом
	b		choosing_loop				// переход к циклу выбора

choosing_loop:
	// Следующие две строчки: копируют MSB r5, записывают в LSB r3
	ubfx	r8, r5, #31, #1				// перезапись r8 текущим рабочим битом (MSB) (r8 = #0 или #1)
	bfi		r3, r8, #0, #1				// запись в r3 LSB

	cmp		r4, #0						// сравнение текущего значения счетчика и числа битов в регистре (дошли до 0?)
	bls		choosing_exit				// тогда (r4 <= 0) выйти из функции
										// иначе:
	lsl		r3, r3, #1					// cдвигаемся к след заполняемой позиции r3 
	lsl		r5, r5, #2					// сдвигаемся след извлекаемой позиции r5
	sub		r4, #1						// вычесть 1 из счетчика

	b		choosing_loop				// новая итерация

choosing_exit:
	pop		{r4, r5, r8}				// выгрузить предыдущие значения использованных регистров
	bx		lr

/*
Регистры:
- r0 - данные верхнего регистра (glob)
- r1 - данные нижнего регистра (glob)
- r2 - регистр-маска для отделения одного бита
- r3 - выходные данные (glob)
- r4 - счетчик битов (15 - 0)
- r5 - служебный регистр для изменения данных
- r6 - регистр для адреса Output регистра порта C
- r7 - регистр для сохранения результата применения маски на r3
- r8 - служебный регистр для правильного копирования бита
*/
output:
	push {r2, r4, r6, r7}				// запись local регистров в стек
	
	mov		r4, #0						// обнуление счетчика битов в регистрах
	ldr		r6, =GPIOC_ODR				// запись адреса регистра вывода в r6
	mov		r2, #1						// создание маски для отделения 0-го бита из r3
	b		output_loop

output_loop:
	and		r7, r3, r2					// применение маски (только 0-ой бит остается)
	str		r7, [r6]					// вывод бита

	bl		delay						// задержка вывода следующего элемента

	cmp		r4, #15						// сравнение текущего значения счетчика и числа битов в регистре
	bhs		output_exit					// тогда (r4 >= 15) выйти из функции
	lsr		r3, r3, #1					// сдвигаемся влево по регистру r3 на 1 бит
	add		r4, r4, #1					// добавить 1 к счетчику

	b 		output_loop					// новая итерация

output_exit:
	str		r2, [r6]					// установка вывода в idle положение
	pop		{r2, r4, r6, r7}			// выгрузить предыдущие значения использованных регистров
	bx		lr


delay:									@ Подпрограмма задержки
	push	{r0}						@ Загружаем в стек R0, т.к. его значение будем менять
	ldr		r0, =0xFFFF					@ псевдоинструкция Thumb (загрузить константу в регистр)
delay_loop:
	subs	r0, #1						@ SUB с установкой флагов результата
	it 		ne
	bne		delay_loop					@ переход, если Z==0 (результат вычитания не равен нулю)
	pop		{r0}						@ Выгружаем из стека R0
	bx		lr							@ выход из подпрограммы (переход к адресу в регистре LR - вершина стека)

  .size Reset_Handler, .-Reset_Handler

/**
 * @brief  This is the code that gets called when the processor receives an
 *         unexpected interrupt.  This simply enters an infinite loop, preserving
 *         the system state for examination by a debugger.
 *
 * @param  None
 * @retval : None
*/
  .section .text.Default_Handler,"ax",%progbits
Default_Handler:
Infinite_Loop:
  b Infinite_Loop
  .size Default_Handler, .-Default_Handler

/******************************************************************************
*
* The STM32F103xx vector table.  Note that the proper constructs
* must be placed on this to ensure that it ends up at physical address
* 0x0000.0000.
*
******************************************************************************/
  .section .isr_vector,"a",%progbits
  .type g_pfnVectors, %object

g_pfnVectors:
  .word _estack
  .word Reset_Handler
  .word NMI_Handler
  .word HardFault_Handler
  .word	MemManage_Handler
  .word	BusFault_Handler
  .word	UsageFault_Handler
  .word	0
  .word	0
  .word	0
  .word	0
  .word	SVC_Handler
  .word	DebugMon_Handler
  .word	0
  .word	PendSV_Handler
  .word	SysTick_Handler
  .word	WWDG_IRQHandler           			/* Window Watchdog interrupt                        */
  .word	PVD_IRQHandler            			/* PVD through EXTI line detection interrupt        */
  .word	TAMPER_IRQHandler         			/* Tamper interrupt                                 */
  .word	RTC_IRQHandler            			/* RTC global interrupt                             */
  .word	FLASH_IRQHandler          			/* Flash global interrupt                           */
  .word	RCC_IRQHandler            			/* RCC global interrupt                             */
  .word	EXTI0_IRQHandler          			/* EXTI Line0 interrupt                             */
  .word	EXTI1_IRQHandler          			/* EXTI Line1 interrupt                             */
  .word	EXTI2_IRQHandler          			/* EXTI Line2 interrupt                             */
  .word	EXTI3_IRQHandler          			/* EXTI Line3 interrupt                             */
  .word	EXTI4_IRQHandler          			/* EXTI Line4 interrupt                             */
  .word	DMA1_Channel1_IRQHandler  			/* DMA1 Channel1 global interrupt                   */
  .word	DMA1_Channel2_IRQHandler  			/* DMA1 Channel2 global interrupt                   */
  .word	DMA1_Channel3_IRQHandler  			/* DMA1 Channel3 global interrupt                   */
  .word	DMA1_Channel4_IRQHandler  			/* DMA1 Channel4 global interrupt                   */
  .word	DMA1_Channel5_IRQHandler  			/* DMA1 Channel5 global interrupt                   */
  .word	DMA1_Channel6_IRQHandler  			/* DMA1 Channel6 global interrupt                   */
  .word	DMA1_Channel7_IRQHandler  			/* DMA1 Channel7 global interrupt                   */
  .word	ADC1_2_IRQHandler         			/* ADC1 and ADC2 global interrupt                   */
  .word	USB_HP_CAN_TX_IRQHandler  			/* USB High Priority or CAN TX interrupts           */
  .word	USB_LP_CAN_RX0_IRQHandler 			/* USB Low Priority or CAN RX0 interrupts           */
  .word	CAN_RX1_IRQHandler        			/* CAN RX1 interrupt                                */
  .word	CAN_SCE_IRQHandler        			/* CAN SCE interrupt                                */
  .word	EXTI9_5_IRQHandler        			/* EXTI Line[9:5] interrupts                        */
  .word	TIM1_BRK_IRQHandler       			/* TIM1 Break interrupt                             */
  .word	TIM1_UP_IRQHandler        			/* TIM1 Update interrupt                            */
  .word	TIM1_TRG_COM_IRQHandler   			/* TIM1 Trigger and Commutation interrupts          */
  .word	TIM1_CC_IRQHandler        			/* TIM1 Capture Compare interrupt                   */
  .word	TIM2_IRQHandler           			/* TIM2 global interrupt                            */
  .word	TIM3_IRQHandler           			/* TIM3 global interrupt                            */
  .word	TIM4_IRQHandler           			/* TIM4 global interrupt                            */
  .word	I2C1_EV_IRQHandler        			/* I2C1 event interrupt                             */
  .word	I2C1_ER_IRQHandler        			/* I2C1 error interrupt                             */
  .word	I2C2_EV_IRQHandler        			/* I2C2 event interrupt                             */
  .word	I2C2_ER_IRQHandler        			/* I2C2 error interrupt                             */
  .word	SPI1_IRQHandler           			/* SPI1 global interrupt                            */
  .word	SPI2_IRQHandler           			/* SPI2 global interrupt                            */
  .word	USART1_IRQHandler         			/* USART1 global interrupt                          */
  .word	USART2_IRQHandler         			/* USART2 global interrupt                          */
  .word	USART3_IRQHandler         			/* USART3 global interrupt                          */
  .word	EXTI15_10_IRQHandler      			/* EXTI Line[15:10] interrupts                      */
  .word	RTCAlarm_IRQHandler       			/* RTC Alarms through EXTI line interrupt           */
  .word	0                         			/* Reserved                                         */
  .word	TIM8_BRK_IRQHandler       			/* TIM8 Break interrupt                             */
  .word	TIM8_UP_IRQHandler        			/* TIM8 Update interrupt                            */
  .word	TIM8_TRG_COM_IRQHandler   			/* TIM8 Trigger and Commutation interrupts          */
  .word	TIM8_CC_IRQHandler        			/* TIM8 Capture Compare interrupt                   */
  .word	ADC3_IRQHandler           			/* ADC3 global interrupt                            */
  .word	FSMC_IRQHandler           			/* FSMC global interrupt                            */
  .word	SDIO_IRQHandler           			/* SDIO global interrupt                            */
  .word	TIM5_IRQHandler           			/* TIM5 global interrupt                            */
  .word	SPI3_IRQHandler           			/* SPI3 global interrupt                            */
  .word	UART4_IRQHandler          			/* UART4 global interrupt                           */
  .word	UART5_IRQHandler          			/* UART5 global interrupt                           */
  .word	TIM6_IRQHandler           			/* TIM6 global interrupt                            */
  .word	TIM7_IRQHandler           			/* TIM7 global interrupt                            */
  .word	DMA2_Channel1_IRQHandler  			/* DMA2 Channel1 global interrupt                   */
  .word	DMA2_Channel2_IRQHandler  			/* DMA2 Channel2 global interrupt                   */
  .word	DMA2_Channel3_IRQHandler  			/* DMA2 Channel3 global interrupt                   */
  .word	DMA2_Channel4_5_IRQHandler			/* DMA2 Channel4 and DMA2 Channel5 global interrupt */
  .size g_pfnVectors, .-g_pfnVectors

/*******************************************************************************
*
* Provide weak aliases for each Exception handler to the Default_Handler.
* As they are weak aliases, any function with the same name will override
* this definition.
*
*******************************************************************************/

	.weak	NMI_Handler
	.thumb_set NMI_Handler,Default_Handler

	.weak	HardFault_Handler
	.thumb_set HardFault_Handler,Default_Handler

	.weak	MemManage_Handler
	.thumb_set MemManage_Handler,Default_Handler

	.weak	BusFault_Handler
	.thumb_set BusFault_Handler,Default_Handler

	.weak	UsageFault_Handler
	.thumb_set UsageFault_Handler,Default_Handler

	.weak	SVC_Handler
	.thumb_set SVC_Handler,Default_Handler

	.weak	DebugMon_Handler
	.thumb_set DebugMon_Handler,Default_Handler

	.weak	PendSV_Handler
	.thumb_set PendSV_Handler,Default_Handler

	.weak	SysTick_Handler
	.thumb_set SysTick_Handler,Default_Handler

	.weak	WWDG_IRQHandler
	.thumb_set WWDG_IRQHandler,Default_Handler

	.weak	PVD_IRQHandler
	.thumb_set PVD_IRQHandler,Default_Handler

	.weak	TAMPER_IRQHandler
	.thumb_set TAMPER_IRQHandler,Default_Handler

	.weak	RTC_IRQHandler
	.thumb_set RTC_IRQHandler,Default_Handler

	.weak	FLASH_IRQHandler
	.thumb_set FLASH_IRQHandler,Default_Handler

	.weak	RCC_IRQHandler
	.thumb_set RCC_IRQHandler,Default_Handler

	.weak	EXTI0_IRQHandler
	.thumb_set EXTI0_IRQHandler,Default_Handler

	.weak	EXTI1_IRQHandler
	.thumb_set EXTI1_IRQHandler,Default_Handler

	.weak	EXTI2_IRQHandler
	.thumb_set EXTI2_IRQHandler,Default_Handler

	.weak	EXTI3_IRQHandler
	.thumb_set EXTI3_IRQHandler,Default_Handler

	.weak	EXTI4_IRQHandler
	.thumb_set EXTI4_IRQHandler,Default_Handler

	.weak	DMA1_Channel1_IRQHandler
	.thumb_set DMA1_Channel1_IRQHandler,Default_Handler

	.weak	DMA1_Channel2_IRQHandler
	.thumb_set DMA1_Channel2_IRQHandler,Default_Handler

	.weak	DMA1_Channel3_IRQHandler
	.thumb_set DMA1_Channel3_IRQHandler,Default_Handler

	.weak	DMA1_Channel4_IRQHandler
	.thumb_set DMA1_Channel4_IRQHandler,Default_Handler

	.weak	DMA1_Channel5_IRQHandler
	.thumb_set DMA1_Channel5_IRQHandler,Default_Handler

	.weak	DMA1_Channel6_IRQHandler
	.thumb_set DMA1_Channel6_IRQHandler,Default_Handler

	.weak	DMA1_Channel7_IRQHandler
	.thumb_set DMA1_Channel7_IRQHandler,Default_Handler

	.weak	ADC1_2_IRQHandler
	.thumb_set ADC1_2_IRQHandler,Default_Handler

	.weak	USB_HP_CAN_TX_IRQHandler
	.thumb_set USB_HP_CAN_TX_IRQHandler,Default_Handler

	.weak	USB_LP_CAN_RX0_IRQHandler
	.thumb_set USB_LP_CAN_RX0_IRQHandler,Default_Handler

	.weak	CAN_RX1_IRQHandler
	.thumb_set CAN_RX1_IRQHandler,Default_Handler

	.weak	CAN_SCE_IRQHandler
	.thumb_set CAN_SCE_IRQHandler,Default_Handler

	.weak	EXTI9_5_IRQHandler
	.thumb_set EXTI9_5_IRQHandler,Default_Handler

	.weak	TIM1_BRK_IRQHandler
	.thumb_set TIM1_BRK_IRQHandler,Default_Handler

	.weak	TIM1_UP_IRQHandler
	.thumb_set TIM1_UP_IRQHandler,Default_Handler

	.weak	TIM1_TRG_COM_IRQHandler
	.thumb_set TIM1_TRG_COM_IRQHandler,Default_Handler

	.weak	TIM1_CC_IRQHandler
	.thumb_set TIM1_CC_IRQHandler,Default_Handler

	.weak	TIM2_IRQHandler
	.thumb_set TIM2_IRQHandler,Default_Handler

	.weak	TIM3_IRQHandler
	.thumb_set TIM3_IRQHandler,Default_Handler

	.weak	TIM4_IRQHandler
	.thumb_set TIM4_IRQHandler,Default_Handler

	.weak	I2C1_EV_IRQHandler
	.thumb_set I2C1_EV_IRQHandler,Default_Handler

	.weak	I2C1_ER_IRQHandler
	.thumb_set I2C1_ER_IRQHandler,Default_Handler

	.weak	I2C2_EV_IRQHandler
	.thumb_set I2C2_EV_IRQHandler,Default_Handler

	.weak	I2C2_ER_IRQHandler
	.thumb_set I2C2_ER_IRQHandler,Default_Handler

	.weak	SPI1_IRQHandler
	.thumb_set SPI1_IRQHandler,Default_Handler

	.weak	SPI2_IRQHandler
	.thumb_set SPI2_IRQHandler,Default_Handler

	.weak	USART1_IRQHandler
	.thumb_set USART1_IRQHandler,Default_Handler

	.weak	USART2_IRQHandler
	.thumb_set USART2_IRQHandler,Default_Handler

	.weak	USART3_IRQHandler
	.thumb_set USART3_IRQHandler,Default_Handler

	.weak	EXTI15_10_IRQHandler
	.thumb_set EXTI15_10_IRQHandler,Default_Handler

	.weak	RTCAlarm_IRQHandler
	.thumb_set RTCAlarm_IRQHandler,Default_Handler

	.weak	TIM8_BRK_IRQHandler
	.thumb_set TIM8_BRK_IRQHandler,Default_Handler

	.weak	TIM8_UP_IRQHandler
	.thumb_set TIM8_UP_IRQHandler,Default_Handler

	.weak	TIM8_TRG_COM_IRQHandler
	.thumb_set TIM8_TRG_COM_IRQHandler,Default_Handler

	.weak	TIM8_CC_IRQHandler
	.thumb_set TIM8_CC_IRQHandler,Default_Handler

	.weak	ADC3_IRQHandler
	.thumb_set ADC3_IRQHandler,Default_Handler

	.weak	FSMC_IRQHandler
	.thumb_set FSMC_IRQHandler,Default_Handler

	.weak	SDIO_IRQHandler
	.thumb_set SDIO_IRQHandler,Default_Handler

	.weak	TIM5_IRQHandler
	.thumb_set TIM5_IRQHandler,Default_Handler

	.weak	SPI3_IRQHandler
	.thumb_set SPI3_IRQHandler,Default_Handler

	.weak	UART4_IRQHandler
	.thumb_set UART4_IRQHandler,Default_Handler

	.weak	UART5_IRQHandler
	.thumb_set UART5_IRQHandler,Default_Handler

	.weak	TIM6_IRQHandler
	.thumb_set TIM6_IRQHandler,Default_Handler

	.weak	TIM7_IRQHandler
	.thumb_set TIM7_IRQHandler,Default_Handler

	.weak	DMA2_Channel1_IRQHandler
	.thumb_set DMA2_Channel1_IRQHandler,Default_Handler

	.weak	DMA2_Channel2_IRQHandler
	.thumb_set DMA2_Channel2_IRQHandler,Default_Handler

	.weak	DMA2_Channel3_IRQHandler
	.thumb_set DMA2_Channel3_IRQHandler,Default_Handler

	.weak	DMA2_Channel4_5_IRQHandler
	.thumb_set DMA2_Channel4_5_IRQHandler,Default_Handler

	.weak	SystemInit

/************************ (C) COPYRIGHT STMicroelectronics *****END OF FILE****/
