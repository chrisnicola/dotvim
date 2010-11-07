" VImChat Plugin for vim
" This plugin allows you to connect to jabber servers and chat with
" multiple people.
"
" It does not currently support other IM networks or group chat, 
" but these are on the list to be added.
"
" It is also worth noting that you can use aim/yahoo via jabber transports,
" but the transports must be set up on another client as vimchat does not
" support setting them up yet
"
" This branchh supports multiple versions at a time, but probably still 
" has a decent amount of bugs!
"
" Note: The vimchat_jid and vimchat_password variables have been *changed*
" into the vimchat_accounts dictionary.  This version of vimchat will not
" work unless you make this change!
"
" Supported ~/.vimrc Variables:
"   g:vimchat_accounts = {'jabber id':'password',...}
"   g:vimchat_buddylistwidth = width of buddy list
"   g:vimchat_libnotify = (0 or 1) default is 1
"   g:vimchat_logpath = path to store log files
"   g:vimchat_logchats = (0 or 1) default is 1
"   g:vimchat_otr = (0 or 1) default is 0
"   g:vimchat_logotr = (0 or 1) default is 1
"   g:vimchat_statusicon = (0 or 1) default is 1


python <<EOF
#{{{ Imports
try:
    import warnings
    warnings.filterwarnings('ignore', category=DeprecationWarning)
    import vim
    import os, os.path, select, threading, xmpp, re, time, sys
    from  ConfigParser import RawConfigParser
    try:
        import simplejson as json
    except:
        try:
            import json
        except:
            pass
except:
    vim.command('let g:vimchat_loaded = 1')

pynotify_enabled = False
try:
    if 'DBUS_SESSION_BUS_ADDRESS' in os.environ:
        import pynotify
        pynotify_enabled = True
    else:
        pynotify_enabled = False
except:
    pynotify_enabled = False

pyotr_enabled = False
pyotr_logging = False
try:
    import otr
    pyotr_logging = True
    pyotr_enabled = True
except:
    pyotr_enabled = False
    pyotr_logging = False


gtk_enabled = False
if 'DISPLAY' in os.environ:
    try:
        from gtk import StatusIcon
        import gtk
        gtk_enabled = True
    except:
        gtk_enabled = False
#}}}

#{{{ VimChatScope
class VimChatScope:
    #Global Variables
    accounts = {}
    groupChatNames = [] # The names you are using in group chats.
    otr_basedir = '~/.vimchat/otr'
    otr_keyfile = 'otrkey'
    otr_fingerprints = 'fingerprints'
    buddyListBuffer = None
    rosterFile = '/tmp/vimChatRoster'
    statusIcon = None
    lastMessageTime = 0

    #{{{ init
    def init(self):
        global pynotify_enabled
        global pyotr_enabled
        global pyotr_logging
        global gtk_enabled
        self.gtk_enabled = gtk_enabled
        self.configFilePath = os.path.expanduser('~/.vimchat/config')

        vim.command('redir! > ~/.vimchat/vimchat.debug')
        vim.command('nnoremap <buffer> B :py VimChat.toggleBuddyList()<CR>')
        vim.command('let s:hasVars = VimChatCheckVars()')
        self.setupLeaderMappings()
        hasVars = int(vim.eval('s:hasVars'))

        if hasVars < 1:
            print "Could not start VimChat!"
            return 0

        #Libnotify
        libnotify = int(vim.eval('g:vimchat_libnotify'))
        if libnotify == 1:
            pynotify_enabled = True
        else:
            pynotify_enabled = False

        otr_enabled = int(vim.eval('g:vimchat_otr'))
        otr_logging = int(vim.eval('g:vimchat_logotr'))
        if otr_enabled == 1:
            if otr_logging == 1:
                pyotr_logging = True
            else:
                pyotr_logging = False
        else:
            pyotr_enabled = False
            pyotr_logging = False

        isStatusIcon = int(vim.eval('g:vimchat_statusicon'))
        if isStatusIcon != 1:
            self.gtk_enabled = False

        if self.gtk_enabled:
            self.statusIcon = self.StatusIcon()
            self.statusIcon.start()

        # Signon to accounts listed in .vimrc
        if vim.eval("exists('g:vimchat_accounts')") == '1':
            vimChatAccounts = vim.eval('g:vimchat_accounts')
            for jid,password in vimChatAccounts.items():
                self._signOn(jid,password)

        # Signon to accounts listed in .vimchat/config
        if os.path.exists(self.configFilePath):
            config = RawConfigParser();
            config.read(self.configFilePath)
            if config.has_section('accounts'):
                for jid in config.options('accounts'):
                    password = config.get('accounts', jid)
                    self._signOn(jid, password)

    #}}}

    #CLASSES
    #{{{ class OtrOps
    class OtrOps:
        #{{{ __init__
        def __init__(self,parent=None):
            self.parent = parent
        #}}}

        #{{{ policy
        def policy(self, opdata=None, context=None):
            """ checks for the contacts username in policylist and returns it
            if available, otherwise checks for a default entry and returns it
            if available, otherwise just return python-otr's default """
            return otr.OTRL_POLICY_DEFAULT
        #}}}
        #{{{ create_privkey
        def create_privkey(self, opdata=None, accountname=None, protocol=None):
            # should give the user some visual feedback here, generating can take some time!
            # the private key MUST be available when this method returned
            print "Need OTR key for: " + accountname + ". :VimChatGenerateKey to create one"
            #TODO
            #VimChat.otrGenerateKey() 
        #}}}
        #{{{ is_logged_in
        def is_logged_in(self, opdata=None, accountname=None, protocol=None, recipient=None):
            if accountname in VimChat.accounts.keys():
                if recipient:
                    priority = VimChat.accounts[accountname]._roster.getPriority(recipient)
                    if priority:
                        return True
                    return False
                else:
                    return False
            else:
                return False
        #}}}
        #{{{ inject_message
        def inject_message(self, opdata=None, accountname=None, protocol=None, recipient=None, message=None):
            if accountname in VimChat.accounts.keys():
                if recipient and message:
                    VimChat.accounts[accountname].jabberSendMessage(recipient, message)
                else:
                    print "Error in inject_message"
        #}}}
        #{{{ notify
        def notify(sef, opdata=None, level=None, accountname=None, protocol=None, username=None, title=None, primary=None, secondary=None):
            # show a small dialog or something like that
            # level is otr.OTRL_NOTIFY_ERROR, otr.OTRL_NOTIFY_WARNING or otr.OTRL_NOTIFY_INFO
            # primary and secondary are the messages that should be displayed
            print "Notify: title: " + title + " primary: " + primary + \
                " secondary: " + secondary
        #}}}
        #{{{ display_otr_message
        def display_otr_message(self, opdata=None, accountname=None, protocol=None, username=None, msg=None):
            # this usually logs to the conversation window

            #write_message(our_account=accountname, proto=protocol, contact=username, message=msg)
            # NOTE: this function MUST return 0 if it processed the message
            # OR non-zero, the message will then be passed to notify() by OTR
            print "Got OTR Message"
            return 0
        #}}}
        #{{{ update_context_list
        def update_context_list(self, opdata=None):
            # this method may provide some visual feedback when the context list was updated
            # this may be useful if you have a central way of setting fingerprints' trusts
            # and you want to update the list of contexts to consider in this way
            pass
        #}}}
        #{{{ protocol_name
        def protocol_name(self, opdata=None, protocol=None):
            """ returns a "human-readable" version of the given protocol """
            if protocol == "xmpp":
                return "XMPP (eXtensible Messaging and Presence Protocol)"
        #}}}
        #{{{ new_fingerprint
        def new_fingerprint(
            self, opdata=None, userstate=None, accountname=None,
            protocol=None, username=None, fingerprint=None):
            
            human_fingerprint = ""
            try:
                human_fingerprint = otr.otrl_privkey_hash_to_human(fingerprint)
                #write_message(our_account=accountname, proto=protocol, contact=username,
                #   message="New fingerprint: %s"%human_fingerprint)
                return human_fingerprint
            except:
                pass
        #}}}
        #{{{ write_fingerprints
        def write_fingerprints(self, opdata=None):
            fpath = os.path.expanduser(
                VimChat.otr_basedir + '/' + VimChat.otr_fingerprints)
            for jid,account in VimChat.accounts.items(): 
                otr.otrl_privkey_write_fingerprints(
                    account._otr_userstate, fpath)
            else:
                print "User: " + str(account) + " not connected"
        #}}}
        #{{{ gone_secure
        def gone_secure(self, opdata=None, context=None):
            trust = context.active_fingerprint.trust
            if trust:
               trust = "V"
            else:
               trust = "U"
            
            buf = VimChat.beginChat(context.accountname, context.username)
            if buf:
                VimChat.appendStatusMessage(context.accountname, 
                    buf,"[OTR]","-- " + trust + " OTR Connection Started")
                print trust+" OTR Connection Started with "+str(context.username)
        #}}}
        #{{{ gone_insecure
        def gone_insecure(self, opdata=None, context=None):
            connection = VimChat.accounts[context.accountname]
            buf = self.getBufByName(connection._chats[context.username])
            if buf:
                VimChat.appendStatusMessage(context.accountname,
                    buf,"[OTR]","-- Secured OTR Connection Ended")
                print "Secure OTR Connection Ended with " + context.username
        #}}}
        #{{{ still_secure
        def still_secure(self, opdata=None, context=None, is_reply=0):
            # this is called when the OTR session was refreshed
            # (ie. new session keys have been created)
            # is_reply will be 0 when we started we started that refresh, 
            #   1 when the contact started it
            try: 
                connection = VimChat.accounts[context.accountname]
                buf = self.getBufByName(connection._chats[context.username])
                if buf:
                    jid = "[OTR]"
                    VimChat.appendStatusMessage(context.accountname, 
                        buf,"[OTR]","-- Secured OTR Connection Refreshed")
                    print "Secure OTR Connection Refreshed with "+str(context.username)
            except Exception, e:
                print "Error in still_secure: " + str(e)
        #}}}
        #{{{ log_message
        def log_message(self, opdata=None, message=None):
            # log message to a logfile or something
            pass
        #}}}
        #{{{ max_message_size
        def max_message_size(self, opdata=None, context=None):
            """ looks up the max_message_size for the relevant protocol """
            # return 0 when no limit is defined
            #return msg_size[context.protocol]
            return 0
        #}}}
        #{{{ account_name
        def account_name(
            self, opdata=None, account=None, context=None, protocol=None):

            #return find_account(accountname=account, protocol).name
            if account in VimChat.accounts.keys(): 
                jid = VimChat.accounts[account]._jid.split('/')[0]
                print "accountname: " + jid
                return jid
            else:
                print "Could not get account name"
        #}}}
    #}}}
    #{{{ class JabberConnection
    class JabberConnection(threading.Thread):

        #{{{ class Variables
        _roster = {}
        _chats = {}
        #}}} 

        #Init Stuff
        #{{{ __init__
        def __init__(self, parent, jid, jabberClient, roster):
            self._parent = parent
            self._jid = jid
            self._jids = jid.split('/')[0]
            self._roster = roster
            threading.Thread.__init__ ( self )
            self.jabber = jabberClient
            self._protocol = 'xmpp'
        #}}}
        #{{{ run
        def run(self):
            self.jabber.RegisterHandler('message',self.jabberMessageReceive)
            self.jabber.RegisterHandler('presence',self.jabberPresenceReceive)
            self.jabberPresenceUpdate()

            #Socket stuff
            RECV_BUF = 4096
            self.xmppS = self.jabber.Connection._sock
            socketlist = [self.xmppS]
            online = 1

            #set up otr
            self.otrSetup()

            while online:
                (i , o, e) = select.select(socketlist,[],[],1)
                for each in i:
                    if each == self.xmppS:
                        self.jabber.Process(1)
                    else:
                        pass
        #}}}

        #From Jabber Functions
        #{{{ jabberMessageReceive
        def jabberMessageReceive(self, conn, msg):
            if msg.getBody():
                fromJid = str(msg.getFrom())
                type = str(msg.getType()).lower()
                jid = fromJid.split('/')[0]
                body = unicode(msg.getBody())
                body = str(body.encode('utf8'))

                if pyotr_enabled and type != "groupchat":
                    #OTR Stuff
                    #{{{ Check for verification stuff
                    is_internal, message, tlvs = otr.otrl_message_receiving(
                        self._otr_userstate, (
                            VimChat.OtrOps(),None),self._jids,self._protocol,jid, body)

                    context = otr.otrl_context_find(
                        self._otr_userstate,jid,self._jids,self._protocol,1)[0]


                    
                    if otr.otrl_tlv_find(tlvs, otr.OTRL_TLV_SMP_ABORT) is not None:
                        self.otrAbortVerify(context)
                    elif otr.otrl_tlv_find(tlvs, otr.OTRL_TLV_SMP1) is not None:
                        if context.smstate.nextExpected != otr.OTRL_SMP_EXPECT1:
                            self.otrAbortVerify(context)
                        else:
                            #TODO: prompt user for secret
                            pass
                    elif otr.otrl_tlv_find(tlvs, otr.OTRL_TLV_SMP1Q) is not None:
                        if context.smstate.nextExpected != otr.OTRL_SMP_EXPECT1:
                            self.otrAbortVerify(context)
                        else:
                            tlv = otr.otrl_tlv_find(tlvs, otr.OTRL_TLV_SMP1Q)
                            VimChat.otrSMPRequestNotify(
                                context.accountname, context.username,tlv.data)
                    elif otr.otrl_tlv_find(tlvs, otr.OTRL_TLV_SMP2) is not None:
                        if context.smstate.nextExpected != otr.OTRL_SMP_EXPECT2:
                            self.otrAbortVerify(context)
                        else:
                            context.smstate.nextExpected = otr.OTRL_SMP_EXPECT4
                    elif otr.otrl_tlv_find(tlvs, otr.OTRL_TLV_SMP3) is not None:
                        if context.smstate.nextExpected != otr.OTRL_SMP_EXPECT3:
                            self.otrAbortVerify(context)
                        else:
                            if context.smstate.sm_prog_state == \
                                otr.OTRL_SMP_PROG_SUCCEEDED:
                                self.otrSMPVerifySuccess(context)
                                print "Successfully verified " + context.username
                            else:
                                self.otrSMPVerifyFailed(context)
                                print "Failed to verify " + context.username
                    elif otr.otrl_tlv_find(tlvs, otr.OTRL_TLV_SMP4) is not None:
                        if context.smstate.nextExpected != otr.OTRL_SMP_EXPECT4:
                            self.otrAbortVerify(context)    
                        else:
                            context.smstate.nextExpected = otr.OTRL_SMP_EXPECT1
                            if context.smstate.sm_prog_state == \
                                otr.OTRL_SMP_PROG_SUCCEEDED:
                                self.otrSMPVerifySuccess(context)
                                print "Successfully verified " + context.username
                            else:
                                self.otrSMPVerifyFailed(context)
                                print "Failed to verify " + context.username
                    #}}}

                    secure = False
                    type = otr.otrl_proto_message_type(body)
                    if type == otr.OTRL_MSGTYPE_DATA \
                        and type != otr.OTRL_MSGTYPE_NOTOTR \
                        and type != otr.OTRL_MSGTYPE_TAGGEDPLAINTEXT:

                        if context.active_fingerprint:
                            trust = context.active_fingerprint.trust
                            if trust:
                                secure = "V"
                            else:
                                secure = "U"

                    if not is_internal:
                        VimChat.messageReceived(self._jids, fromJid, message.strip(),secure)

                elif type == "groupchat":
                    parts = fromJid.split('/')
                    chatroom = parts[0]
                    if len(parts) > 1:
                        user = parts[1]
                    else:
                        user = "--"
                    VimChat.messageReceived(
                        self._jids, user, body.strip(), False, chatroom)
                else:
                    VimChat.messageReceived(self._jids, fromJid,body.strip())
        #}}}
        #{{{ jabberPresenceReceive
        def jabberPresenceReceive(self, conn, msg):
            #TODO: figure out better way than this try/except block
            try:
                fromJid = msg.getFrom()
                type = str(msg.getType()).lower()
                show = str(unicode(msg.getShow()).encode('utf-8'))
                status = str(unicode(msg.getStatus()).encode('utf-8'))
                priority = str(unicode(msg.getPriority()).encode('utf-8'))
                #print fromJid, ' jid: ', msg.getJid(), ' status: ', status, ' reason: ', msg.getReason(), ' stat code: ', msg.getStatusCode()

                if show == "None":
                    if priority != "None":
                        show = 'online'
                    else:
                        show = 'offline'

                if type == "groupchat":
                    parts = fromJid.split('/')
                    chatroom = parts[0]
                    user = ""
                    if len(parts) > 1:
                        user = parts[1]

                    VimChat.presenceUpdate(self._jids,
                        str(chatroom), str(user), show,status,priority)
                else:
                    VimChat.presenceUpdate(self._jids,
                        str(fromJid), fromJid,show,status,priority)
            except:
                pass
        #}}}

        #To Jabber Functions
        #{{{ jabberOnSendMessage
        def jabberOnSendMessage(self, tojid, msg):
            msg = msg.strip()
            if not pyotr_enabled:
                self.jabberSendMessage(tojid,msg)
                return 0

            #only if otr is enabled
            new_message = otr.otrl_message_sending(
                self._otr_userstate,(VimChat.OtrOps(),None),
                self._jids,self._protocol,tojid,msg,None)
                
            context = otr.otrl_context_find(
                self._otr_userstate,tojid,self._jids,self._protocol,1)[0]

            #if context.msgstate == otr.OTRL_MSGSTATE_ENCRYPTED
            otr.otrl_message_fragment_and_send(
                (VimChat.OtrOps(),None),context,new_message,otr.OTRL_FRAGMENT_SEND_ALL)
        #}}}
        #{{{ jabberSendMessage
        def jabberSendMessage(self, tojid, msg):
            msg = msg.strip()
            m = xmpp.protocol.Message(to=tojid,body=msg,typ='chat')
            self.jabber.send(m)
        #}}}
        #{{{ jabberSendGroupChatMessage
        def jabberSendGroupChatMessage(self, room, msg):
            msg = msg.strip()
            m = xmpp.protocol.Message(to=room,body=msg,typ='groupchat')
            self.jabber.send(m)
        #}}}
        #{{{ jabberJoinGroupChat
        def jabberJoinGroupChat(self, room, name):
            roomStr = room + '/' + name
            self.jabber.send(xmpp.Presence(to=roomStr))
        #}}}
        #{{{ jabberLeaveGroupChat
        def jabberLeaveGroupChat(self, room):
            self.jabber.send(xmpp.Presence(to=room,typ='unavailable'))
        #}}}
        #{{{ jabberPresenceUpdate
        def jabberPresenceUpdate(self, show='', status='', priority=5):
            m = xmpp.protocol.Presence(
                None,
                show=show,
                priority=priority,
                status=status)
            self._presence = m
            self.jabber.send(m)
        #}}}
        #{{{ jabberGetPresence
        def jabberGetPresence(self):
            show = self._presence.getShow()
            status = self._presence.getStatus()
            return [show,status]
        #}}}
        #{{{ disconnect
        def disconnect(self):
            try:
                self.jabber.disconnect()
            except:
                pass
        #}}}
        #{{{ isConnected
        def isConnected(self):
            return self.jabber.isConnected()
        #}}}

        #Roster Functions
        #{{{ getRosterItems
        def getRosterItems(self):
            if self._roster:
                return self._roster.getItems()
            else:
                return None
        #}}}

        #OTR Functions
        #{{{ otrSetup
        def otrSetup(self):
            #Set Up OTR Stuff If Available
            if not pyotr_enabled:
                return 0

            self._otr_userstate = otr.otrl_userstate_create()

            keypath = os.path.expanduser(
                VimChat.otr_basedir + '/' + VimChat.otr_keyfile)

            #Make the otr directory
            basedir = os.path.expanduser(VimChat.otr_basedir)
            if not os.path.exists(basedir):
                os.makedirs(basedir)

            if not os.path.isfile(keypath):
                #Create it if it doesn't exist
                file(keypath,'w')
                jid = self._jid.split('/')[0]

                print "No OTR Key found for " + self._jids + \
                    ".  :VimChatOtrGenerateKey to make one."
            else:
                pass
                if os.access(keypath, os.R_OK):
                    try:
                        otr.otrl_privkey_read(self._otr_userstate,keypath)
                    except:
                        pass


            fprintPath = os.path.expanduser(
                VimChat.otr_basedir + '/' + VimChat.otr_fingerprints)
            if not os.path.isfile(fprintPath):
                #Create it if it doesn't exist
                file(fprintPath,'w')
            else:
                if os.access(fprintPath, os.R_OK):
                    try:
                        otr.otrl_privkey_read_fingerprints(
                            self._otr_userstate,fprintPath)
                    except:
                        pass
        #}}}
        #{{{ otrDisconnectChat
        def otrDisconnectChat(self, jid):
            context = otr.otrl_context_find(
                self._otr_userstate,jid,self._jids,self._protocol,1)[0]

            if context.msgstate == otr.OTRL_MSGSTATE_ENCRYPTED:
                otr.otrl_message_disconnect(
                    self._otr_userstate,(VimChat.OtrOps(),None),
                    self._jids,self._protocol,jid)
        #}}}
        #{{{ otrManualVerifyBuddy
        def otrManualVerifyBuddy(self, jid):
            self.otrSetTrust(jid,"manual")
            buf = VimChat.beginChat(self._jids, jid)
            if buf:
                VimChat.appendStatusMessage( self._jids,
                    buf,"[OTR]","-- Verified Fingerprint of " + jid)
                print "Verified "+jid
        #}}}
        #{{{ otrSMPVerifyBuddy
        def otrSMPVerifyBuddy(self, jid, question, secret):
            context = otr.otrl_context_find(
                self._otr_userstate,jid,self._jids,self._protocol,1)[0]

            otr.otrl_message_initiate_smp_q(
                self._otr_userstate,(VimChat.OtrOps(), None),context,question,secret)

            buf = VimChat.beginChat(self._jids, jid)
            if buf:
                VimChat.appendMessage(context.accountname,
                    buf,"-- Sent Question to "+ jid +" for verification.")
                print "Sent Question for verification to "+str(context.username)
        #}}}
        #{{{ otrSMPVerifySuccess
        def otrSMPVerifySuccess(self,context):
            jid = context.username
            self.otrSetTrust(jid,"smp") 
            buf = VimChat.beginChat(context.accountname, jid)
            if buf:
                VimChat.appendStatusMessage(context.accountname, 
                    buf,"[OTR]",
                    "-- Secret answered! "+ jid +" is verified.")
                print jid + " Gave correct secret -- verified!"
        #}}}
        #{{{ otrSMPVerifyFailed
        def otrSMPVerifyFailed(self,context):
            jid = context.username
            self.otrSetTrust(jid,"") 
            buf = VimChat.beginChat(context.accountname, jid)
            if buf:
                VimChat.appendStatusMessage(context.accountname,
                    buf,"[OTR]",
                    "-- Secret response Failed! "+ jid + " is NOT verified.")
                print jid + " Failed to answer secret, NOT verified!"
        #}}}
        #{{{ otrSMPRespond
        def otrSMPRespond(self,jid,secret):
            context = otr.otrl_context_find(
                self._otr_userstate,jid,self._jids,self._protocol,1)[0]

            otr.otrl_message_respond_smp(
                self._otr_userstate,(VimChat.OtrOps(),None),context,secret)
            buf = VimChat.beginChat(self._jids, jid)
            if buf:
                VimChat.appendStatusMessage(context.accountname,
                    buf,"[OTR]","-- Sent Secret to "+ jid +"")
                print "Sent secret response to " + jid
        #}}}
        #{{{ otrGeneratePrivateKey
        def otrGeneratePrivateKey(self):
            keypath = os.path.expanduser(
                VimChat.otr_basedir + '/' + VimChat.otr_keyfile)
            jid = self._jid.split('/')[0]
            otr.otrl_privkey_generate(
                self._otr_userstate, keypath, jid, self._protocol)
        #}}}
        #{{{ otrAbortVerify
        def otrAbortVerify(self,context):
            otr.otrl_message_abort_smp(
                self._otr_userstate, (VimChat.OtrOps(), None), context)
        #}}}
        #{{{ otrSetTrust
        def otrSetTrust(self, jid, trust):
            context = otr.otrl_context_find(
                self._otr_userstate,jid,self._jids,self._protocol,1)[0]
            otr.otrl_context_set_trust(context.active_fingerprint,trust)
        #}}}
        #{{{ otrIsChatEncrypted
        def otrIsChatEncrypted(self, account, jid):
            context = otr.otrl_context_find(
                VimChat.accounts[account]._otr_userstate,jid,
                VimChat.accounts[account]._jids,
                VimChat.accounts[account]._protocol,1)[0]

            if context.msgstate == otr.OTRL_MSGSTATE_ENCRYPTED:
                return True
            else:
                return False
        #}}}
    #}}}
    #{{{ class StatusIcon
    class StatusIcon(threading.Thread):
        def run(self):
            # GTK StausIcon
            gtk.gdk.threads_init()
            self.status_icon = StatusIcon()
            self.status_icon.set_from_file(os.path.expanduser(
                '~/.vimchat/icon.gif'))
            self.status_icon.set_tooltip("VimChat")
            self.status_icon.set_visible(True)
            gtk.main()
        def blink(self, value):
            self.status_icon.set_blinking(value)
    #}}}

    #CONNECTION FUNCTIONS
    #{{{ signOn
    def signOn(self):
        accounts = self.getAccountsFromConfig()
        if len(accounts) == 0:
            print 'No acounts found in the vimchat config %s.'\
                % (self.configFilePath)
            return
        for account in accounts:
            print account
        account = vim.eval(
            'input("Enter the account from the above list: ")')
        if account in accounts:
            password = accounts[account]
            self._signOn(account, password)
        else:
            print 'Error: [%s] is an invalid account.' % (account)
    #}}}
    #{{{ _signOn
    def _signOn(self, jid, password):
        if not password:
            password = vim.eval('inputsecret("' + jid + ' password: ")')
        [jidSmall,user,resource] = self.getJidParts(jid)
        print "Connecting user " + jid + "..."
        if jidSmall in self.accounts:
            try: self.accounts[jidSmall].disconnect()
            except: pass

        JID=xmpp.protocol.JID(jid)
        jabberClient = xmpp.Client(JID.getDomain(),debug=[])

        con = jabberClient.connect()
        if not con:
            print 'could not connect!\n'
            return 0

        auth=jabberClient.auth(
            JID.getNode(), password, resource=JID.getResource())
        if not auth:
            print 'could not authenticate!\n'
            return 0

        jabberClient.sendInitPresence(requestRoster=1)
        roster = jabberClient.getRoster()

        [accountJid,user,resource] = self.getJidParts(jid)
        if accountJid in self.accounts:
            try:
                self.accounts[accountJid].disconnect()
            except: pass
        self.accounts[accountJid] = self.JabberConnection(
            self, jid, jabberClient, roster)
        self.accounts[accountJid].start()

        print "Connected with " + jid
    #}}}
    #{{{ signOff
    def signOff(self):
        accounts = self.accounts
        if len(accounts) == 0:
            print 'No acounts found'
            return
        for account in accounts:
            print account
        account = vim.eval(
            'input("Enter the account from the above list: ")')
        self._signOff(account)
    #}}}
    #{{{ _signOff
    def _signOff(self, account):
        accounts = self.accounts
        if account in accounts:
            try:
                accounts[account].disconnect()
                del accounts[account]
                print "Signed Off VimChat!"
            except:
                print "Error signing off %s VimChat!" % (account)
                print sys.exc_info()[0:2]
        else:
            print 'Error: [%s] is an invalid account.' % (account)
    #}}}
    #{{{ showStatus
    def showStatus(self):
        print self.accounts[self.accounts.keys()[0]].jabberGetPresence()
    #}}}

    #HELPER FUNCTIONS
    #{{{ formatPresenceUpdateLine
    def formatPresenceUpdateLine(self, fromJid, show, status):
        tstamp = self.getTimestamp()
        return tstamp + " -- " + str(fromJid) + \
            " is " + str(show) + ": " + str(status)
    #}}}
    #{{{ getJidParts
    def getJidParts(self, jid):
        jidParts = str(jid).split('/')
        # jid: bob@foo.com
        jid = jidParts[0]
        # user: bob
        user = jid.split('@')[0]

        #Get A Resource if exists
        if len(jidParts) > 1:
            resource = jidParts[1]
        else:
            resource = ''

        return [jid,user,resource]
    #}}}
    #{{{ getTimestamp
    def getTimestamp(self):
        return time.strftime("[%H:%M]")
    #}}}
    #{{{ getBufByName
    def getBufByName(self, name):
        for buf in vim.buffers:
            if buf.name and buf.name.split('/')[-1] == name:
                return buf
        return None
    #}}}
    #{{{ isGroupChat
    def isGroupChat(self):
        try:
            groupchat = int(vim.eval('b:groupchat'))
            if groupchat == 1:
                return True
        except:
            pass

        return False
    #}}}

    #BUDDY LIST
    #{{{ toggleBuddyList
    def toggleBuddyList(self):
        # godlygeek's way to determine if a buffer is hidden in one line:
        #:echo len(filter(map(range(1, tabpagenr('$')), 'tabpagebuflist(v:val)'), 'index(v:val, 4) == 0'))

        if not self.accounts:
            print "Not Connected!  Please connect first."
            return 0

        if self.buddyListBuffer:
            bufferList = vim.eval('tabpagebuflist()')
            if str(self.buddyListBuffer.number) in bufferList:
                vim.command('sbuffer ' + str(self.buddyListBuffer.number))
                vim.command('hide')
                return

        #Write buddy list to file
        self.writeBuddyList()

        buddyListWidth = vim.eval('g:vimchat_buddylistwidth')

        try:
            vim.command("silent vertical sview " + self.rosterFile)
            vim.command("silent wincmd H")
            vim.command("silent vertical resize " + buddyListWidth)
            vim.command("silent e!")
            vim.command("setlocal noswapfile")
            vim.command("setlocal nomodifiable")
            vim.command("setlocal buftype=nowrite")
        except Exception, e:
            print e
            vim.command("new " + self.rosterFile)


        commands = """
        setlocal foldtext=VimChatFoldText()
        setlocal nowrap
        setlocal foldmethod=marker
        nmap <buffer> <silent> <CR> :py VimChat.beginChatFromBuddyList()<CR>
        nnoremap <buffer> <silent> <Leader>l :py VimChat.openLogFromBuddyList()<CR>
        nnoremap <buffer> <silent> B :py VimChat.toggleBuddyList()<CR>
        nnoremap <buffer> <silent> q :py VimChat.toggleBuddyList()<CR>
        nnoremap <buffer> <silent> <Leader>c :py VimChat.openGroupChat()<CR>
        nnoremap <buffer> <silent> <Leader>ss :py VimChat.setStatus()<CR>
        nnoremap <buffer> <silent> <Space> :silent exec 'vertical resize ' . (winwidth('.') > g:vimchat_buddylistwidth ? (g:vimchat_buddylistwidth) : '')<CR>
        """

        vim.command(commands)
        self.setupLeaderMappings()

        self.buddyListBuffer = vim.current.buffer
    #}}}
    #{{{ getBuddyListItem
    def getBuddyListItem(self, item):
        if item == 'jid':
            vim.command("normal zo")
            vim.command("normal ]z")
            vim.command("normal [z")
            vim.command("normal j")

            toJid = vim.current.line
            toJid = toJid.strip()
            
            vim.command("normal zc")
            vim.command("normal [z")

            account = str(vim.current.line).split(' ')[2]

            return account, toJid
    #}}}
    #{{{ beginChatFromBuddyList
    def beginChatFromBuddyList(self):
        account, toJid = self.getBuddyListItem('jid')
        [jid,user,resource] = self.getJidParts(toJid)

        buf = VimChat.beginChat(account, jid)
        if not buf:
            #print "Error getting buddy info: " + jid
            return 0


        vim.command('sbuffer ' + str(buf.number))
        VimChat.toggleBuddyList()
        vim.command('wincmd K')
    #}}}
    #{{{ writeBuddyList
    def writeBuddyList(self):
        #write roster to file
        import codecs
        rF = codecs.open(self.rosterFile,'w','utf-16')

        for curJid, account in self.accounts.items():
            if not account.isConnected():
                rF.write(
u"""
******************************
ERROR: %s IS NOT CONNECTED!!!
You can type \on to reconnect.
******************************
""" % (curJid))
                continue
            accountText = u"{{{ [+] %s\n"%(curJid)
            rF.write(accountText)

            roster = account._roster
            rosterItems = roster.getItems()
            rosterItems.sort()
            for item in rosterItems:
                name = roster.getName(item)
                status = roster.getStatus(item)
                show = roster.getShow(item)
                priority = roster.getPriority(item)
                groups = roster.getGroups(item)

                if not name:
                    name = item
                if not status:
                    status = u''
                if not show:
                    if priority:
                        show = u'on'
                    else:
                        show = u'off'
                if not priority:
                    priority = u''
                if not groups:
                    groups = u''
                
                if show != u'off':
                    buddyText =\
                        u"{{{ (%s) %s\n\t%s \n\tGroups: %s\n\t%s:\n%s\n}}}\n" %\
                        (show, name, item, groups, show, status)
                    rF.write(buddyText)

            rF.write("}}}\n")

        rF.close()
    #}}}

    #CHAT BUFFERS
    #{{{ beginChat
    def beginChat(self, fromAccount, toJid, groupChat = False):
        #return 0
        #Set the ChatFile
        connection = self.accounts[fromAccount]
        if toJid in connection._chats.keys():
            chatFile = connection._chats[toJid]
        else:
            if groupChat:
                chatFile = 'groupchat:' + toJid
            else:
                chatFile = 'chat:' + toJid

            connection._chats[toJid] = chatFile

        bExists = int(vim.eval('buflisted("' + chatFile + '")'))
        if bExists: 
            #TODO: Need to call sbuffer only if buffer is hidden.
            #vim.command('sbuffer ' + chatFile)
            return self.getBufByName(chatFile)
        else:
            vim.command("split " + chatFile.replace('%', r'\%'))
            #Only do this stuff if its a new buffer
            if groupChat:
                vim.command('let b:groupchat=1')
            else:
                vim.command('let b:groupchat=0')

            vim.command("let b:buddyId = '" + toJid + "'")
            vim.command("let b:account = '" + fromAccount + "'")
            self.setupChatBuffer(groupChat);
            return vim.current.buffer

    #}}}
    #{{{ setupChatBuffer
    def setupChatBuffer(self, isGroupChat=False):
        commands = """
        setlocal noswapfile
        setlocal buftype=nowrite
        setlocal noai
        setlocal nocin
        setlocal nosi
        setlocal filetype=vimchat
        setlocal syntax=vimchat
        setlocal wrap
        setlocal foldmethod=marker
        nnoremap <buffer> <silent> i :py VimChat.sendBufferShow()<CR>
        nnoremap <buffer> <silent> o :py VimChat.sendBufferShow()<CR>
        nnoremap <buffer> <silent> a :py VimChat.sendBufferShow()<CR>
        nnoremap <buffer> <silent> B :py VimChat.toggleBuddyList()<CR>
        nnoremap <buffer> <silent> q :py VimChat.deleteChat()<CR>
        au CursorMoved <buffer> exe 'py VimChat.clearNotify()'
        """
        vim.command(commands)
        self.setupLeaderMappings()
        if isGroupChat:
            vim.command('setlocal foldmethod=syntax')
    #}}}
    #{{{ setupLeaderMappings
    def setupLeaderMappings(self):
        commands = """
        nnoremap <buffer> <silent> <Leader>l :py VimChat.openLogFromChat()<CR>
        nnoremap <buffer> <silent> <Leader>ov :py VimChat.otrVerifyBuddy()<CR>
        nnoremap <buffer> <silent> <Leader>or :py VimChat.otrSmpRespond()<CR>
        nnoremap <buffer> <silent> <Leader>c :py VimChat.openGroupChat()<CR>
        nnoremap <buffer> <silent> <Leader>j :py VimChat.joinChatroom()<CR>
        nnoremap <buffer> <silent> <Leader>on :py VimChat.signOn()<CR>
        nnoremap <buffer> <silent> <Leader>off :py VimChat.signOff()<CR>
        """
        vim.command(commands)
    #}}}
    #{{{ sendBufferShow
    def sendBufferShow(self):
        toJid = vim.eval('b:buddyId')
        account = vim.eval('b:account')
        groupChat = vim.eval('b:groupchat')

        #Create sending buffer
        sendBuffer = "sendTo:" + toJid
        vim.command("silent bo new " + sendBuffer)
        vim.command("silent let b:buddyId = '" + toJid +  "'")
        vim.command("silent let b:account = '" + account +  "'")
        vim.command("setlocal filetype=vimchat")

        commands = """\
            resize 4
            setlocal noswapfile
            setlocal nocin
            setlocal noai
            setlocal nosi
            setlocal buftype=nowrite
            setlocal wrap
            setlocal foldmethod=marker
            noremap <buffer> <silent> <CR> :py VimChat.sendMessage()<CR>
            inoremap <buffer> <silent> <CR> <Esc>:py VimChat.sendMessage()<CR>
            nnoremap <buffer> <silent> q :hide<CR>
        """
        vim.command(commands)
        vim.command('normal G')
        vim.command('normal o')
        vim.command('normal zt')
        vim.command('star')
        vim.command('let b:groupchat=' + str(groupChat))

    #}}}
    #{{{ appendMessage
    def appendMessage(
        self, account, buf, message, showJid='Me',secure=False):

        if not buf:
            print "VimChat: Invalid Buffer to append to!"
            return 0

        lines = message.split("\n")
        tstamp = self.getTimestamp()

        jid,user,resource = self.getJidParts(showJid)
        logJid = buf.name.split('/')[-1].split(':')[1]
        
        secureString = ""
        if secure:
            secureString = "(*" + secure + "*)"

        #Get the first line
        if resource:
            line = tstamp + secureString + \
                user + "/" + resource + ": " + lines.pop(0);
        else:
            line = tstamp + secureString + user + ": " + lines.pop(0);

        buf.append(line)
        #TODO: remove these lines
        #line = line.replace("'", "''")
        #vim.command("call append(line('$'),'" + line + "')")
        if not secure or pyotr_logging:
            VimChat.log(account, logJid, line)

        for line in lines:
            line = '\t' + line
            buf.append(line)
            #line = line.replace("'", "''")
            #vim.command("call append(line('$'),'" + line + "')")
            #if message is not secure, or if otr logging is on
            if not secure or pyotr_logging:
                VimChat.log(account, logJid, line)

        #move cursor to bottom of buffer
        self.moveCursorToBufBottom(buf)
    #}}}
    #{{{ appendStatusMessage
    def appendStatusMessage(self, account, buf, prefix, message):
        if not buf:
            print "VimChat: Invalid Buffer to append to!"
            return 0
        
        jid = buf.name.split('/')[-1].split(':')[1]
        jid,user,resource = self.getJidParts(jid)

        lines = message.split("\n")
        tstamp = self.getTimestamp()

        #Get the first line
        line = tstamp + prefix + ": " + lines.pop(0);

        buf.append(line)
        VimChat.log(account, jid, line)

        for line in lines:
            line = '\t' + line
            buf.append(line)
            VimChat.log(account, jid, line)

        #move cursor to bottom of buffer
        #self.moveCursorToBufBottom(buf)
    #}}}
    #{{{ deleteChat
    def deleteChat(self):
        #remove it from chats list
        jid = vim.eval('b:buddyId')
        account = vim.eval('b:account')

        if pyotr_enabled:
            self.accounts[account].otrDisconnectChat(jid)

        del self.accounts[account]._chats[jid]

        #Check if it was a groupchat
        if self.isGroupChat():
            self.accounts[account].jabberLeaveGroupChat(jid)
        vim.command('bdelete!')
    #}}}
    #{{{ openGroupChat
    def openGroupChat(self):
        accounts = self.showAccountList()

        input = vim.eval(
            'input("Account (enter the number from the above list): ")')
        if not re.match(r'\d+$', input):
            vim.command('echohl ErrorMsg')
            vim.command('echo "\\nYou must enter an integer corresponding'
                + ' to an account."')
            vim.command('echohl None')
            return
        index = int(input)
        if index < 0 or index >= len(accounts):
            vim.command('echohl ErrorMsg')
            vim.command(r'echo "\nInvalid account number. Try again."')
            vim.command('echohl None')
            return

        account = accounts[index]
        chatroom = vim.eval('input("Chat Room to join: ")')
        name = vim.eval('input("Name to Use: ")')
        self._openGroupChat(account, chatroom, name)
    #}}}
    #{{{ _openGroupChat
    def _openGroupChat(self, account, chatroom, name):
        self.groupChatNames.append(name)
        buf = VimChat.beginChat(account._jids, chatroom, True)
        vim.command('sbuffer ' + str(buf.number))
        account.jabberJoinGroupChat(chatroom, name)
    #}}}
    #{{{ echoError
    def echoError(self, msg):
        vim.command('echohl ErrorMsg')
        vim.command(r'echo "\n"')
        vim.command("echo '" + msg.replace("'", "''") + "'")
        vim.command('echohl None')
    #}}}
    #{{{ joinChatroom
    def joinChatroom(self):
        if not os.path.exists(self.configFilePath):
            print 'Error: Config file %s does not exist' % (self.configFilePath)
            return

        chatrooms = {}
        try:
            config = RawConfigParser()
            config.read(self.configFilePath)
            for section in config.sections():
                if not section.startswith('chatroom:'):
                    continue
                tokens = section.split(':')
                if len(tokens) < 2:
                    continue
                roomAlias = tokens[1]
                data = {}
                data['account'] = config.get(section, 'account')
                data['room'] = config.get(section, 'room')
                data['username'] = config.get(section, 'username')
                chatrooms[roomAlias] = data
        except:
            print 'Error: Problems reading the vimchat config %s.'\
                % (self.configFilePath)
            print sys.exc_info()[0], sys.exc_info()[1]
            return

        for room in chatrooms:
            print room
        input = vim.eval(
            'input("Enter the room name from the above list: ")')
        if input in chatrooms:
            self._openGroupChat(self.accounts[chatrooms[input]['account']],
                chatrooms[input]['room'], chatrooms[input]['username'])
        else:
            print 'Error: [%s] is an invalid chatroom.' % (input)
    #}}}
    #{{{ moveCursorToBufBottom
    def moveCursorToBufBottom(self, buf):
        # TODO: Need to make sure this only happens if this buffer doesn't
        # have focus.  Otherwise, this hijacks the users cursor.
        return
        for w in vim.windows:
            if w.buffer == buf:
                w.cursor = (len(buf), 0)
    #}}}

    #ACCOUNT
    #{{{ showAccountList
    def showAccountList(self):
        accounts = []
        i = 0
        for jid,account in self.accounts.items():
            accounts.append(account)
            print str(i) + ": " + jid
            i = i + 1

        return accounts
    #}}}
    #{{{ getAccountsFromConfig
    def getAccountsFromConfig(self):
        accounts = {}
        if not os.path.exists(self.configFilePath):
            print 'Error: Config file %s does not exist' % (self.configFilePath)
            return {}
        try:
            config = RawConfigParser()
            config.read(self.configFilePath)
            for account in config.options('accounts'):
                accounts[account] = config.get('accounts', account)
        except:
            print 'Error reading accounts from the vimchat config %s.'\
                % (self.configFilePath), sys.exc_info()[0:2]
            return {}
        return accounts
    #}}}

    #LOGGING
    #{{{ log
    def log(self, account, user, msg):
        logChats = int(vim.eval('g:vimchat_logchats'))
        if logChats > 0:
            logPath = vim.eval('g:vimchat_logpath')
            logDir = \
                os.path.expanduser(logPath + '/' + account + '/' + user)
            if not os.path.exists(logDir):
                os.makedirs(logDir)

            day = time.strftime('%Y-%m-%d')
            log = open(logDir + '/' + user + '-' + day, 'a')
            log.write(msg + '\n')
            log.close()
    #}}}
    #{{{ openLogFromBuddyList
    def openLogFromBuddyList(self):
        account, jid = VimChat.getBuddyListItem('jid')
        VimChat.openLog(account, jid)
    #}}}
    #{{{ openLogFromChat
    def openLogFromChat(self):
        try:
            jid = vim.eval('b:buddyId')
        except:
            print "You may only open the log from a chat buffer"
            return
        account = vim.eval('b:account')
        if jid != '' and account != '':
            VimChat.openLog(account, jid)
        else:
            print "Invalid chat window!"
    #}}}
    #{{{ openLog
    def openLog(self, account, jid):
            logPath = vim.eval('g:vimchat_logpath')
            logDir = \
                os.path.expanduser(logPath + '/' + account + '/' + jid)
            print logDir
            if not os.path.exists(logDir):
                print "No Logfile Found"
                return 0
            else:
                print "Opening log for: " + logDir
                vim.command('tabe ' + logDir)
    #}}}

    #OUTGOING
    #{{{ sendMessage
    def sendMessage(self):
        try:
            toJid = vim.eval('b:buddyId')
            account = vim.eval('b:account')
        except:
            print "No valid chat found!"
            return 0

        connection = self.accounts[account]
        chatBuf = self.getBufByName(connection._chats[toJid])
        if not chatBuf:
            print "Chat Buffer Could not be found!"
            return 0

        r = vim.current.range
        body = ""
        for line in r:
            body = body + line + '\n'

        body = body.strip()

        if self.isGroupChat():
            connection.jabberSendGroupChatMessage(toJid, body)
        else:
            connection.jabberOnSendMessage(toJid, body)
        
        secure = False

        if pyotr_enabled:
            secure = connection.otrIsChatEncrypted(account, toJid)
            if secure:
                secure = "e"

        if not self.isGroupChat():
            VimChat.appendMessage(account, chatBuf,body,'Me',secure)


        vim.command('hide')
        vim.command('sbuffer ' + str(chatBuf.number))
        vim.command('normal G')
    #}}}
    #{{{ setStatus
    def setStatus(self, status=None):
        if not status:
            status = str(vim.eval('input("Status: (away,xa,dnd,chat),message,priority: ")'))

        parts = status.split(',')
        show = parts[0]
        status = ''
        priority = 10
        if len(parts) > 1:
            status = parts[1]
        if len(parts) > 2:
            priority = parts[2]

        for jid,account in self.accounts.items():
            account.jabberPresenceUpdate(show,status,priority)

        print "Updated status to: " + str(priority) + " -- " + show + " -- " + status
    #}}}

    #INCOMING
    #{{{ presenceUpdate
    def presenceUpdate(self, account, chat, fromJid, show, status, priority):
        try:
            #Only care if we have the chat window open
            fullJid = fromJid
            [fromJid,user,resource] = self.getJidParts(fromJid)
            [chat,nada,nada2] = self.getJidParts(fromJid)

            connection = VimChat.accounts[account]
            
            if chat in connection._chats.keys():
                #Make sure buffer exists
                chatFile = connection._chats[fromJid]
                if chatFile.startswith('groupchat'):
                    return
                chatBuf = self.getBufByName(chatFile)
                bExists = int(vim.eval('buflisted("' + chatFile + '")'))
                if chatBuf and bExists:
                    statusUpdateLine = self.formatPresenceUpdateLine(fullJid,show,status)
                    if chatBuf[-1] != statusUpdateLine:
                        chatBuf.append(statusUpdateLine)
                        self.moveCursorToBufBottom(chatBuf)
                else:
                    #Should never get here!
                    print "Buffer did not exist for: " + fromJid
        except Exception, e:
            print "Error in presenceUpdate: " + str(e)

    #}}}
    #{{{ messageReceived
    def messageReceived(self, account, fromJid, message, secure=False, groupChat=""):
        #Store the buffer we were in
        origBufNum = vim.current.buffer.number

        # Commented out the next 2 lines.  For some reason, when the orig
        # buffer is the buddy list, it causes a bug that makes it so you
        # don't receive any more messages.
        #
        #if origBufNum == self.buddyListBuffer.number:
        #    vim.command('wincmd w')

        #Get Jid Parts
        [jid,user,resource] = self.getJidParts(fromJid)

        if groupChat:
            if re.search('has (joined|quit|part).+\(.=.+@.+\)$', message):
                return
            buf = VimChat.beginChat(account, groupChat)
        else:
            buf = VimChat.beginChat(account, jid)

        try:
            VimChat.appendMessage(account, buf, message, fromJid, secure)
        except:
            print 'Error zzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzz'
            print 'could not appendMessage:', message, 'from:', fromJid

        # Highlight the line.
        # TODO: This only works if the right window has focus.  Otherwise it
        # highlights the wrong lines.
        # vim.command("call matchadd('Error', '\%' . line('$') . 'l')")

        try:
            self.notify(jid, message, groupChat)
        except:
            print 'Error zzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzz'
            print 'could not notify:', message, 'from:', jid
    #}}}
    #{{{ notify
    def notify(self, jid, msg, groupChat):
        # Important to keep this echo statement.  As a side effect, it
        # refreshes the buffer so the new message shows up. Need to find
        # a better solution though.
        vim.command("echo 'Message Received from: " + jid.replace("'", "''")
            + "'")

        if groupChat:
            msgLowered = msg.lower()
            myNames = map(lambda x: x.split('@')[0], self.accounts.keys())
            myNames.extend(self.groupChatNames)
            myNames = map(lambda x: x.lower(), myNames)
            foundMyName = False
            for name in myNames:
                if name in msgLowered:
                    foundMyName = True
                    print (jid + ' said your name in #'
                        + groupChat.split('%')[0].split('@')[0])
                    break
            if not foundMyName:
                return

        vim.command("set tabline=%#Error#New-message-from-" + jid);

        if pynotify_enabled and 'DBUS_SESSION_BUS_ADDRESS' in os.environ:
            pynotify.init('vimchat')
            n = pynotify.Notification(jid + ' says: ', msg, 'dialog-warning')
            n.set_timeout(10000)
            n.show()

        if self.gtk_enabled:
            self.statusIcon.blink(True)
    #}}}
    #{{{ clearNotify
    def clearNotify(self):
        vim.command('set tabline&')
        if self.gtk_enabled:
            self.statusIcon.blink(False)
    #}}}

    #OTR
    #{{{ otrVerifyBuddy
    def otrVerifyBuddy(self):
        if not pyotr_enabled:
            print "OTR Not enabled!"
            return 0
        try:
            jid = vim.eval('b:buddyId')
            account = vim.eval('b:account')
        except:
            print "Invalid chat buffer!"
            return

        response = str(vim.eval('input("Verify ' + jid + \
            ' (1:manual, 2:Question/Answer): ")'))
        if response == "1":
            response2 = str(vim.eval("input('Verify buddy? (y/n): ')")).lower()
            if response2 == "y":
                self.accounts[account].otrManualVerifyBuddy(jid)
            else:
                print "Verify Aborted."
        elif response == "2":
            question = vim.eval('input("Enter Your Question: ")')
            secret = vim.eval('inputsecret("Enter your secret answer: ")')
            self.accounts[account].otrSMPVerifyBuddy(jid,question,secret)
        else:
            print "Invalid Response."
    #}}}
    #{{{ otrGenerateKey
    def otrGenerateKey(self):
        if not pyotr_enabled:
            print "Otr not enabled!"
            return 0

        accounts = self.showAccountList()

        try:
            response = int(vim.eval("input('Account: ')"))

            if response < len(accounts):
                print "Generating Key for " + \
                    accounts[response]._jids + "(please bear with us)..."
                accounts[response].otrGeneratePrivateKey()
                print "Generated OTR Key!"
            else:
                print "Not Generating Key Now."
        except:
            print "Error generating key!"
    #}}}
    #{{{ otrSMPRequestNotify
    def otrSMPRequestNotify(self, account, jid, question):
        if not pyotr_enabled:
            return 0

        buf = VimChat.beginChat(account, jid)
        if buf:
            message = "-- OTR Verification Request received!  " + \
                "Press <Leader>or to answer the question below:\n" + question
            VimChat.appendMessage(account, buf,message, "[OTR]")
            print "OTR Verification Request from " + jid
    #}}}
    #{{{ otrSmpRespond
    def otrSmpRespond(self):
        if not pyotr_enabled:
            return 0

        try:
            jid = vim.eval('b:buddyId')
            account = vim.eval('b:account')
        except:
            print "Invalid chat buffer!"
            return

        response = str(vim.eval(
                "inputsecret('Answer to "+ jid +": ')")).lower() 
        self.accounts[account].otrSMPRespond(jid, response) 
    #}}}
#}}}
VimChat = VimChatScope()

EOF

"{{{ Vim Commands
if exists('g:vimchat_loaded')
    finish
endif
let g:vimchat_loaded = 1

com! VimChat py VimChat.init() 
com! VimChatBuddyList py VimChat.toggleBuddyList()
com! VimChatViewLog py VimChat.openLogFromChat()
com! VimChatJoinGroupChat py VimChat.openGroupChat()
com! VimChatOtrVerifyBuddy py VimChat.otrVerifyBuddy()
com! VimChatOtrSMPRespond py VimChat.otrSmpRespond()
com! VimChatOtrGenerateKey py VimChat.otrGenerateKey()
com! -nargs=0 VimChatSetStatus py VimChat.setStatus(<args>)
com! VimChatShowStatus py VimChat.showStatus()
com! VimChatJoinChatroom py VimChat.joinChatroom()

set switchbuf=usetab

"}}}
"{{{ VimChatCheckVars
fu! VimChatCheckVars()
    if !exists('g:vimchat_buddylistwidth')
        let g:vimchat_buddylistwidth=30
    endif
    if !exists('g:vimchat_libnotify')
        let g:vimchat_libnotify=1
    endif
    if !exists('g:vimchat_logpath')
        let g:vimchat_logpath="~/.vimchat/logs"
    endif
    if !exists('g:vimchat_logchats')
        let g:vimchat_logchats=1
    endif
    if !exists('g:vimchat_otr')
        let g:vimchat_otr=0
    endif
    if !exists('g:vimchat_logotr')
        let g:vimchat_logotr=1
    endif
    if !exists('g:vimchat_statusicon')
        let g:vimchat_statusicon=1
    endif

    return 1
endfu
"}}}
"{{{ VimChatFoldText
function! VimChatFoldText()
    let line=substitute(getline(v:foldstart),'^[ \t#]*\([^=]*\).*', '\1', '')
    let line=strpart('                                     ', 0, (v:foldlevel - 1)).substitute(line,'\s*{\+\s*', '', '')
    return line
endfunction
"}}}

" vim:et:fdm=marker:sts=4:sw=4:ts=4
