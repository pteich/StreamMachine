_u = require '../lib/underscore'
{EventEmitter}  = require "events"
http = require "http"
icecast = require("icecast-stack")

module.exports = class Caster extends EventEmitter
    DefaultOptions:
        source:         null
        port:           8080
        meta_interval:  10000
        name:           "Caster"
        title:          "Welcome to Caster"
    
    #----------
    
    constructor: (options) ->
        @options = _u(_u({}).extend(@DefaultOptions)).extend( options || {} )

        if !@options.source
            console.error "No source for broadcast!"
            
        # attach to source
        @source = @options.source
        
        # listener count
        @listeners = 0
                    
        # set up shoutcast listener
        @server = http.createServer (req,res) => @_handle(req,res)
        @server.listen(@options.port)
        console.log "caster is listening on port #{@options.port}"
        
        # for debugging information
        @source.on "data", (chunk) =>
            console.log "Listeners: #{@listeners}"
        
    #----------
    
    registerListener: (obj) ->
        @listeners += 1
        
    #----------
    
    closeListener: (obj) ->
        @listeners -= 1
    
    #----------
            
    _handle: (req,res) ->
        console.log "in _handle for caster request"
        
        # -- parse request to see what we're giving back -- #
        
        if req.url == "/stream.mp3"
            console.log "Asked for stream.mp3"
            
            icyMeta = if req.headers['icy-metadata'] == 1 then true else false

            if icyMeta
                # -- create a shoutcast broadcaster instance -- #
                new Caster.Shoutcast(req,res,@)
                
            else
                # -- create a straight mp3 listener -- #
                console.log "no icy-metadata requested...  straight mp3"
                new Caster.LiveMP3(req,res,@)
        
        else if req.url == "/listen.pls"
            # -- return shoutcast playlist -- #
            res.writeHead 200, 
                "Content-Type": "audio/x-scpls"
                "Connection":   "close"
            
            res.end( 
                """
                [playlist]
                NumberOfEntries=1
                File1=http://localhost:#{@options.port}/stream.mp3
                """   
            )             
        else
            res.write "Nope..."
    
    #----------            
            
    class @Shoutcast
        constructor: (req,res,caster) ->
            @req = req
            @res = res
            @caster = caster
            
            console.log "registered shoutcast client"
            
            # convert this into an icecast response
            @res = new icecast.IcecastWriteStack @res, @caster.options.meta_interval
            res.queueMetadata StreamTitle:"Welcome to Caster", StreamURL:""
            
            headers = 
                "Content-Type":         "audio/mpeg"
                "Connection":           "close"
                "Transfer-Encoding":    "identity"
                "icy-name":             @caster.options.name
                "icy-metaint":          @caster.options.meta_interval
                
            # register ourself as a listener
            @caster.registerListener(@)
            
            # write out our headers
            res.writeHead 200, headers
            
            @metaFunc = (data) =>
                if data.streamTitle
                    @res.queueMetadata data
                    
            @caster.source.on "metadata", @metaFunc      
            
            @dataFunc = (chunk) => @res.write(chunk)

            # and start sending data...
            @caster.source.on "data", @dataFunc
                                
            @req.connection.on "close", =>
                # stop listening to stream
                @caster.source.removeListener "data", @dataFunc
                
                # and to metadata
                @caster.source.removeListener "metadata", @metaFunc
                
                # tell the caster we're done
                @caster.closeListener(@)
            
            
    #----------        
            
    class @LiveMP3
        constructor: (req,res,caster) ->
            @req = req
            @res = res
            @caster = caster                
            
            headers = 
                "Content-Type":         "audio/mpeg"
                "Connection":           "close"
                "Transfer-Encoding":    "identity"
                
            # register ourself as a listener
            @caster.registerListener(@)
            
            # write out our headers
            res.writeHead 200, headers
            
            @dataFunc = (chunk) => @res.write(chunk)

            # and start sending data...
            @caster.source.on "data", @dataFunc
                                
            @req.connection.on "close", =>
                # stop listening to stream
                @caster.source.removeListener "data", @dataFunc
                
                # tell the caster we're done
                @caster.closeListener(@)
            
    #----------