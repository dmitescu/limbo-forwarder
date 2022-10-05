# SPDX-License-Identifier: LGPL-3.0-or-later
# Copyright (C) 2022 Authors M. G. Dan

implement Forwarder;

include "sys.m";
include "dial.m";
include "draw.m";

sys:  Sys;
dial: Dial;

debug: int;

Forwarder: module {
	init:	   fn(ctxt: ref Draw->Context, argv: list of string);
	stream_wh: fn(src: ref Dial->Connection, dst_dfd: ref Sys->FD, stat: chan of int);
	stream_rh: fn(src: ref Dial->Connection, dst_dfd: ref Sys->FD, stat: chan of int);
	loop:      fn(src: string, dst: string, child_channel: chan of int);
};


stream_wh(src: ref Dial->Connection, dst_dfd: ref Sys->FD, stat: chan of int) {
	buffer := array[Sys->ATOMICIO] of byte;
	for(;;) { alt {
		stat_message := <- stat => {
			if (debug)
				sys->print("closing forwarding connection to %s\n", dial->netinfo(src).raddr);
			return;
		}
		* => while((n := sys->read(src.dfd, buffer, len buffer)) > 0) {
			res := sys->write(dst_dfd, buffer, n);
			if (res < 1) {
				if (debug)
					sys->print("closing forwarding connection to %s\n", dial->netinfo(src).raddr);
				stat <- = 0;
				return;
			}
			if (debug)
				sys->print("%s wrote %d bytes\n", dial->netinfo(src).raddr, res);
			}
		}}
}

stream_rh(src: ref Dial->Connection, dst_dfd: ref Sys->FD, stat: chan of int) {
	buffer := array[Sys->ATOMICIO] of byte;
	for(;;) { alt {
		stat_message := <- stat => {
			if (debug)
				sys->print("closing forwarding connection to %s\n", dial->netinfo(src).raddr);
			return;
		}
		* => while((n := sys->read(dst_dfd, buffer, len buffer)) > 0) {
			res := sys->write(src.dfd, buffer, n);
			if (res < 1) {
				if (debug)
					sys->print("closing forwarding connection to %s\n", dial->netinfo(src).raddr);
				stat <- = 0;
				return;
			}
			if (debug)
				sys->print("%s read %d bytes\n", dial->netinfo(src).raddr, res);
		}
	}}
}

loop(src: string, dst: string, child_channel: chan of int) {
	sys->pctl(Sys->NEWFD|Sys->FORKNS|Sys->NEWPGRP, list of {0, 1, 2});
	
	dst_an := dial->announce(dst);
	if (dst_an == nil) {
		sys->print("unable to listen on %s: %r\n", dst);
		child_channel <-= -1;
		return;
	}
	
	for(;;) { 
		dst_conn := dial->listen(dst_an);
		if (dst_conn == nil) {
			sys->print("cannot listen: %r\n");
			child_channel <-= -1;
			return;
		}
		
		dst_dfd := dial->accept(dst_conn);
		if (dst_dfd == nil) {
			sys->print("unable to connect to %s: %r\n", src);
			child_channel <-= -1;
			return;
		}
		
		src_conn := dial->dial(src, nil);
		status_channel := chan of int;

		spawn stream_rh(src_conn, dst_dfd, status_channel);
		spawn stream_wh(src_conn, dst_dfd, status_channel);
	}

	child_channel <-= 0;
}

#
# entrypoint
#
init(nil: ref Draw->Context, argv: list of string)
{
	sys = load Sys Sys->PATH;
	dial = load Dial Dial->PATH;

	abort := 0;
	debug = 0;
	daemonize := 1;
	src: string;
	dst: string;
	
	arg_stack := tl argv;
	while (len arg_stack > 0) {
		case (hd arg_stack) {
			"-d" => debug = 1;
			"-F" => daemonize = 0;
			* => {
				if (src == nil)
					src = hd arg_stack;
				else if (dst == nil)
					dst = hd arg_stack;
				else
					abort = 1;
			}
		}
		arg_stack = tl arg_stack;
	}

	if (src == nil || dst == nil) {
		abort = 1;
	}

	if (abort) {
		sys->print("usage: svc/forwarder [-d] [-F] src dst\n");
		exit;
	}

	child_channel := chan of int;

	spawn loop(src, dst, child_channel);
	if (!daemonize) {
		<-child_channel;
	}
}

