implement Topic;

include "sys.m";
	sys : Sys;
	Qid, nulldir, OTRUNC: import sys;
include "draw.m";
include "styx.m";
	styx : Styx;
	Tmsg, Rmsg : import styx;
include "styxservers.m";
	styxservers : Styxservers;
	Styxserver, Navigator, Fid : import styxservers;
	nametree : Nametree;
	Tree : import nametree;

Topic : module
{
	init: fn(nil : ref Draw->Context, argv: list of string);
};

Qroot, Qctl, Qmsgs, Qnewmsg, Qmsgdir : con big iota;

uid : string;

init (nil: ref Draw->Context, argv: list of string)
{
	sys  = load Sys Sys->PATH;
	styx = load Styx Styx->PATH;
	styx->init();
	styxservers = load Styxservers Styxservers->PATH;
	styxservers->init(styx);
	nametree = load Nametree Nametree->PATH;
	nametree->init();

	getuid();
	(tree, treeop) := nametree->start();
	tree.create(Qroot, dir(".", 8r777|Sys->DMDIR, Qroot));
	tree.create(Qroot, dir("ctl", 8r666|sys->OTRUNC, Qctl));
	tree.create(Qroot, dir("msgs", 8r666, Qmsgs));
	tree.create(Qroot, dir("newmsg", 8r666, Qnewmsg));

	nav := Navigator.new(treeop);
	(tchan, srv) := Styxserver.new(sys->fildes(0), nav, Qroot);
	spawn server(tchan, srv, tree);
}

getuid()
{
        buf := array [100] of byte;
        fd := sys->open("/dev/user", Sys->OREAD);
        uidlen := sys->read(fd, buf, len buf);
        uid = string buf[0: uidlen];
}

dir(name: string, perm: int, qid: big): Sys->Dir
{
	d := sys->zerodir;
	d.name = name;
	d.uid = uid;
	d.gid = uid;
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
	readerId : int = 0;

	sys->pctl(Sys->NEWPGRP, nil);

	while((gm := <-tchan) != nil){
		pick m := gm{
		Wstat => # workaround for linux v9fs O_TRUNC issue
			srv.reply(ref Rmsg.Wstat(m.tag));
		Readerror =>
			break;
		Flush =>
			srv.reply(ref Rmsg.Flush(m.tag));
		Write =>
			(c, err) := srv.canwrite(m);
			if (c == nil){
				srv.reply(ref Rmsg.Error(m.tag, err));
			} else{
				srv.reply(ref Rmsg.Write(m.tag, len m.data));
			}
		Read =>
			(c, err) := srv.canread(m);
			if (c == nil)
				srv.reply(ref Rmsg.Error(m.tag, err));

			case c.path{
			Qmsgs =>
				data := array of byte "TODO: list of messages here";
				srv.reply(styxservers->readbytes(m, data));
			Qnewmsg =>
				data := array of byte string "from: \ndate: \n";
				srv.reply(styxservers->readbytes(m, data));
			* =>
				srv.default(gm);
			}
		* => srv.default(gm);
		}
	}
	tree.quit();
}

newmsgclient(fid: int, name: string)
{
    #writemsgclients(fid, nil, "+++ " + name + " has arrived");
    #msgclients = ref Msgclient(fid, name, keptmsg, nil, msgclients);
}

