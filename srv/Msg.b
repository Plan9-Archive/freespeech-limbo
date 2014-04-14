implement Msg;

include "sys.m";
	sys : Sys;
include "draw.m";
include "styx.m";
	styx : Styx;
	Tmsg, Rmsg : import styx;
include "styxservers.m";
	styxservers : Styxservers;
	Styxserver, Navigator : import styxservers;
	nametree : Nametree;
	Tree : import nametree;

Msg : module
{
	init: fn(nil : ref Draw->Context, argv: list of string);
};

Qroot, Qctl, Qbody : con big iota;

init (nil: ref Draw->Context, argv: list of string)
{
	sys  = load Sys Sys->PATH;
	styx = load Styx Styx->PATH;
	styx->init();
	styxservers = load Styxservers Styxservers->PATH;
	styxservers->init(styx);
	nametree = load Nametree Nametree->PATH;
	nametree->init();

	(tree, treeop) := nametree->start();
	tree.create(Qroot, dir(".", 8r555|Sys->DMDIR, Qroot));
	tree.create(Qroot, dir("ctl", 8r666, Qctl));
	tree.create(Qroot, dir("body", 8r666, Qbody));

	nav := Navigator.new(treeop);
	(tchan, srv) := Styxserver.new(sys->fildes(0), nav, Qroot);
	spawn server(tchan, srv, tree);
}

dir(name: string, perm: int, qid: big): Sys->Dir
{
	d := sys->zerodir;
	d.name = name;
	d.uid = "monitor";
	d.gid = "monitor";
	d.qid.path = qid;
	if (perm & Sys->DMDIR)
		d.qid.qtype = Sys->QTDIR;
	else
		d.qid.qtype = Sys->QTFILE;
		d.mode = perm;
	return d;
}

server(tchan: chan of ref Tmsg, srv: ref Styxserver, tree: ref Tree)
{
	sys->pctl(Sys->NEWPGRP, nil);

	while((gm := <-tchan) != nil){
		pick m := gm{
		Write =>
			(c, err) := srv.canwrite(m);
			if (c == nil){
				srv.reply(ref Rmsg.Error(m.tag, err));
			} else if (c.path == Qctl){
				srv.reply(ref Rmsg.Write(m.tag, len m.data));
			}
		Read =>
			(c, err) := srv.canread(m);
			if (c == nil)
				srv.reply(ref Rmsg.Error(m.tag, err));

			case c.path{
			Qbody =>
				data := array of byte "TODO: message body here";
				srv.reply(styxservers->readbytes(m, data));
			* =>
				srv.default(gm);
			}
		* => srv.default(gm);
		}
	}
	tree.quit();
}
