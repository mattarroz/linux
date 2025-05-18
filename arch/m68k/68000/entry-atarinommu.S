/* SPDX-License-Identifier: GPL-2.0-or-later
 * -*- mode: asm -*-
 *
 *  linux/arch/m68k/kernel/entry-atarinommu.S
 *
 *  Copyright (C) 1991, 1992  Linus Torvalds
 *
 * Linux/m68k support by Hamish Macdonald
 *
 * 68060 fixes by Jesper Skov
 *
 */

/*
 * entry.S  contains the system-call and fault low-level handling routines.
 * This also contains the timer-interrupt handler, as well as all interrupts
 * and faults that can result in a task-switch.
 *
 * NOTE: This code handles signal-recognition, which happens every time
 * after a timer-interrupt and after each system call.
 *
 */

/*
 * 12/03/96 Jes: Currently we only support m68k single-cpu systems, so
 *               all pointers that used to be 'current' are now entry
 *               number 0 in the 'current_set' list.
 *
 *  6/05/00 RZ:	 addedd writeback completion after return from sighandler
 *		 for 68040
 */

#include <linux/linkage.h>
#include <asm/errno.h>
#include <asm/setup.h>
#include <asm/traps.h>
#include <asm/unistd.h>
#include <asm/asm-offsets.h>
#include <asm/entry.h>



.globl system_call, buserr, trap, resume
.globl sys_call_table
.globl __sys_fork, __sys_clone, __sys_vfork
.globl bad_interrupt
.globl auto_irqhandler_fixup
.globl user_irqvec_fixup
.globl auto_inthandler1
.globl auto_inthandler2
.globl user_inthandler1
.globl user_inthandler2

.text
ENTRY(__sys_fork)
	SAVE_SWITCH_STACK
	jbsr	sys_fork
	lea     %sp@(24),%sp
	rts

ENTRY(__sys_clone)
	SAVE_SWITCH_STACK
	pea	%sp@(SWITCH_STACK_SIZE)
	jbsr	m68k_clone
	lea     %sp@(28),%sp
	rts

ENTRY(__sys_vfork)
	SAVE_SWITCH_STACK
	jbsr	sys_vfork
	lea     %sp@(24),%sp
	rts

ENTRY(__sys_clone3)
	SAVE_SWITCH_STACK
	pea	%sp@(SWITCH_STACK_SIZE)
	jbsr	m68k_clone3
	lea	%sp@(28),%sp
	rts

ENTRY(sys_sigreturn)
	SAVE_SWITCH_STACK
	movel	%sp,%a1			  	| switch_stack pointer
	lea	%sp@(SWITCH_STACK_SIZE),%a0	| pt_regs pointer
	lea     %sp@(-84),%sp			| leave a gap
	movel	%a1,%sp@-
	movel	%a0,%sp@-
	jbsr	do_sigreturn
	jra	1f				| shared with rt_sigreturn()

ENTRY(sys_rt_sigreturn)
	SAVE_SWITCH_STACK
	movel	%sp,%a1			  	| switch_stack pointer
	lea	%sp@(SWITCH_STACK_SIZE),%a0	| pt_regs pointer
	lea     %sp@(-84),%sp			| leave a gap
	movel	%a1,%sp@-
	movel	%a0,%sp@-
	| stack contents:
	|   [original pt_regs address] [original switch_stack address]
	|   [gap] [switch_stack] [pt_regs] [exception frame]
	jbsr	do_rt_sigreturn

1:
	| stack contents now:
	|   [original pt_regs address] [original switch_stack address]
	|   [unused part of the gap] [moved switch_stack] [moved pt_regs]
	|   [replacement exception frame]
	| return value of do_{rt_,}sigreturn() points to moved switch_stack.

	movel	%d0,%sp				| discard the leftover junk
	RESTORE_SWITCH_STACK
	| stack contents now is just [syscall return address] [pt_regs] [frame]
	| return pt_regs.d0
	movel	%sp@(PT_OFF_D0+4),%d0
	rts

ENTRY(buserr)
	SAVE_ALL_INT
	GET_CURRENT(%d0)
	movel	%sp,%sp@-		| stack frame pointer argument
	jbsr	buserr_c
	addql	#4,%sp
	jra	ret_from_exception

ENTRY(trap)
	SAVE_ALL_INT
	GET_CURRENT(%d0)
	movel	%sp,%sp@-		| stack frame pointer argument
	jbsr	trap_c
	addql	#4,%sp
	jra	ret_from_exception

	| After a fork we jump here directly from resume,
	| so that %d1 contains the previous task
	| schedule_tail now used regardless of CONFIG_SMP
ENTRY(ret_from_fork)
	movel	%d1,%sp@-
	jsr	schedule_tail
	addql	#4,%sp
	jra	ret_from_exception

ENTRY(ret_from_kernel_thread)
	| a3 contains the kernel thread payload, d7 - its argument
	movel	%d1,%sp@-
	jsr	schedule_tail
	movel	%d7,(%sp)
	jsr	%a3@
	addql	#4,%sp
	jra	ret_from_exception


.altmacro
.macro create_auto_inthandler iter
ENTRY(auto_inthandler\iter)
	SAVE_ALL_INT
	movel	%sp,%sp@-
	movel	#\iter,%sp@-
.if \iter == 1
auto_irqhandler_fixup = . + 2 // FIXME(mreis): +2 correct?
.endif
	jsr	do_IRQ
	addql	#8,%sp
	jra	ret_from_exception
.endm


.set i, 1
.rept 7
	create_auto_inthandler %i
	.set i, i+1
.endr

.macro create_user_inthandler iter
ENTRY(user_inthandler\iter)
	SAVE_ALL_INT
.if \iter == 1
	user_irqvec_fixup = . + 2 /* FIXME_Matthias: not sure if it is enough to have
							   * this only at this point or if all other
							   * user_inthandlers need that as well
							   */
.endif
	movel	%sp,%sp@-
	movel	#(8+\iter-1),%sp@-	|  (user ints starting at 8)
	jsr	do_IRQ
	addql	#8,%sp
	jra	ret_from_exception
.endm


.set i, 1
.rept 192
	create_user_inthandler %i
	.set i, i+1
.endr

.macro create_trap iter, trapnumber
ENTRY(trap\iter)
	movew	#\trapnumber,%sp@-
	subql	#4,%sp
	movew	%sr,%sp@-
	SAVE_ALL_INT
	GET_CURRENT(%d0)
	movel	%sp,%sp@-
	jsr	trap_c			|  process the IRQ
	addql	#4,%sp			|  pop parameters off stack
	jra	ret_from_exception
.endm

.set i, 1
.rept 15
	create_trap %i, (VEC_TRAP1 + i - 1)
	.set i, i+1
.endr

create_trap _vec_addrerr, VEC_ADDRERR
create_trap _vec_illegal, VEC_ILLEGAL
create_trap _vec_line10, VEC_LINE10
create_trap _vec_line11, VEC_LINE11
create_trap _vec_priv, VEC_PRIV
create_trap _vec_coproc, VEC_COPROC
create_trap _vec_fpbruc, VEC_FPBRUC
create_trap _vec_fpoe, VEC_FPOE
create_trap _vec_fpnan, VEC_FPNAN
create_trap _vec_fpir, VEC_FPIR
create_trap _vec_fpdivz, VEC_FPDIVZ
create_trap _vec_fpunder, VEC_FPUNDER
create_trap _vec_fpover, VEC_FPOVER
create_trap _vec_zerodiv, VEC_ZERODIV
create_trap _vec_chk, VEC_CHK
create_trap _vec_trap, VEC_TRAP
create_trap _vec_trace, VEC_TRACE

ENTRY(bad_inthandler)
	SAVE_ALL_INT

	movel	%sp,%sp@-
	jsr	handle_badint
	addql	#4,%sp
	jra	ret_from_exception


badsys:
	movel	#-ENOSYS,%sp@(PT_OFF_D0)
	jra	ret_from_exception

do_trace:
	movel	#-ENOSYS,%sp@(PT_OFF_D0) /* needed for strace*/
	subql	#4,%sp
	SAVE_SWITCH_STACK
	jbsr	syscall_trace_enter
	RESTORE_SWITCH_STACK
	addql	#4,%sp
	addql	#1,%d0
	jeq	ret_from_exception
	movel	%sp@(PT_OFF_ORIG_D0),%d1
	movel	#-ENOSYS,%d0
	cmpl	#NR_syscalls,%d1
	jcc	1f
	lsl	#2,%d1
	lea	sys_call_table, %a0
	jbsr	%a0@(%d1)

1:	movel	%d0,%sp@(PT_OFF_D0)	/* save the return value */
	subql	#4,%sp			/* dummy return address */
	SAVE_SWITCH_STACK
	jbsr	syscall_trace_leave
	RESTORE_SWITCH_STACK
	addql	#4,%sp
	jra	ret_from_exception

ENTRY(system_call)
	SAVE_ALL_SYS

	/* save top of frame*/
	pea	%sp@
	jbsr	set_esp0
	addql	#4,%sp

	movel	%sp@(PT_OFF_ORIG_D0),%d0

	movel	%sp,%d1			/* get thread_info pointer */
	andl	#-THREAD_SIZE,%d1
	movel	%d1,%a2
	btst	#(TIF_SYSCALL_TRACE%8),%a2@(TINFO_FLAGS+(31-TIF_SYSCALL_TRACE)/8)
	jne	do_trace
	cmpl	#NR_syscalls,%d0
	jcc	badsys
	lsl	#2,%d0
	lea	sys_call_table,%a0
	movel	%a0@(%d0), %a0
	jbsr	%a0@
	movel	%d0,%sp@(PT_OFF_D0)	/* save the return value*/

ret_from_exception:
	btst	#5,%sp@(PT_OFF_SR)	/* check if returning to kernel*/
	jeq	Luser_return		/* if so, skip resched, signals*/

Lkernel_return:
	RESTORE_ALL

Luser_return:
	/* only allow interrupts when we are really the last one on the*/
	/* kernel stack, otherwise stack overflow can occur during*/
	/* heavy interrupt load*/
	andw	#ALLOWINT,%sr

	movel	%sp,%d1			/* get thread_info pointer */
	andl	#-THREAD_SIZE,%d1
	movel	%d1,%a2
1:
	move	%a2@(TINFO_FLAGS),%d1	/* thread_info->flags */
	jne	Lwork_to_do
	RESTORE_ALL

Lwork_to_do:
	movel	%a2@(TINFO_FLAGS),%d1	/* thread_info->flags */
	btst	#TIF_NEED_RESCHED,%d1
	jne	reschedule

Lsignal_return:
	subql	#4,%sp			/* dummy return address*/
	SAVE_SWITCH_STACK
	pea	%sp@(SWITCH_STACK_SIZE)
	bsrw	do_notify_resume
	addql	#4,%sp
	RESTORE_SWITCH_STACK
	addql	#4,%sp
	jra	1b


/*
 * Beware - when entering resume, prev (the current task) is
 * in a0, next (the new task) is in a1, so don't change these
 * registers until their contents are no longer needed.
 */
ENTRY(resume)
	movel	%a0,%d1				/* save prev thread in d1 */
	movew	%sr,%a0@(TASK_THREAD+THREAD_SR)	/* save sr */
	SAVE_SWITCH_STACK
	movel	%sp,%a0@(TASK_THREAD+THREAD_KSP) /* save kernel stack */
	movel	%usp,%a3			/* save usp */
	movel	%a3,%a0@(TASK_THREAD+THREAD_USP)

	movel	%a1@(TASK_THREAD+THREAD_USP),%a3 /* restore user stack */
	movel	%a3,%usp
	movel	%a1@(TASK_THREAD+THREAD_KSP),%sp /* restore new thread stack */
	RESTORE_SWITCH_STACK
	movew	%a1@(TASK_THREAD+THREAD_SR),%sr	/* restore thread status reg */
	rts
                                                                                                                        
ENTRY(reschedule)
	/* save top of frame */
	pea	%sp@
	jbsr	set_esp0
	addql	#4,%sp
	pea	ret_from_exception
	jmp	schedule

ENTRY(ret_from_user_signal)
	moveq #__NR_sigreturn,%d0
	trap #0

ENTRY(ret_from_user_rt_signal)
	movel #__NR_rt_sigreturn,%d0
	trap #0
