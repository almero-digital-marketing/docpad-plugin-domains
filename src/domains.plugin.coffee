module.exports = (BasePlugin) ->
    # Define Plugin
    class Domains extends BasePlugin
        # Plugin Name
        name: 'domains'
        config:
            domains: []
            files: []

        extendTemplateData: (opts) ->
            # Prepare
            docpad = @docpad
            config = @config
            documents = docpad.getCollection('documents')
            {templateData} = opts
            notFound = []

            templateData.dd = (rel, document, domainName) ->
                document ?= @getDocument()

                domainDocument = undefined
                isSameDomain = domainName is undefined
                if not domainName?
                    domainName = document.domainName
                    domainName ?= document.get('domainName') if document.get?
                    domainName ?= 'default'
                
                if docpad.domainMap[domainName]?
                    domainDocument = docpad.domainMap[domainName][rel]
                    if domainDocument?
                        domainDocument = domainDocument.toJSON()
                        if isSameDomain
                            if document.get('isPaged') != true and document.get('standalone') != true and document.get('rel')?
                                document.set('referencesOthers', true)
                            domainDocument.rdp = document.get('ptr') + domainDocument.absoluteDomainPath
                        else
                            domainDocument.rdp = 'http://' + domainName + domainDocument.absoluteDomainPath
                    else 
                        isFoundIn = (term, array) -> array.indexOf(term) isnt -1
                        if document.get('domain')?
                            notFoundDocument = document.get('domain').name + rel
                            if not isFoundIn notFoundDocument, notFound
                                notFound.push(notFoundDocument)
                                docpad.log('warn', 'Domain document not found /' + domainName + rel, document.get('relativeOutPath'))
                        else
                            notFoundDocument = rel
                            if not isFoundIn notFoundDocument, notFound
                                notFound.push(notFoundDocument)
                            docpad.log('warn', 'Domain document not found ' + rel, document.get('relativeOutPath'))
                return domainDocument

            templateData.df = (absolutePath, absoluteDomainPath, domainName) ->
                if not domainName?
                    document = @getDocument()
                    domainName ?= document.get('domainName')
                    return if not domainName?
                    if not absoluteDomainPath?
                        absoluteDomainPath = absolutePath

                config.files.push { 'absolutePath': absolutePath, 'absoluteDomainPath': absoluteDomainPath, 'domainName': domainName }
                return absoluteDomainPath

            templateData.getDomainCollection = (collection, document, domainName) ->
                document ?= @getDocument()
                if not domainName?
                    domainName = document.domainName
                    domainName ?= document.get('domainName') if document.get?
                    domainName ?= 'default'
                
                if docpad.domainMap[domainName]?
                    if domainName != 'default'
                        docpad.getCollection(collection).findAllLive({'domainName': domainName})
                    else
                        docpad.log 'warn', 'Get collection domain is missing', collection
                        docpad.getCollection(collection)
                else
                    return undefined     

            templateData.getAlternates = (document) ->
                document ?= @getDocument()
                rel = document.get('rel')
                if rel?
                    documents = docpad.getCollection('documents')
                    alternates = documents.findAll({'rel':rel}).toJSON()
                else
                    alternates = []
                alternates

            templateData.getDomainUrl = (document) ->
                document ?= @getDocument()
                return '/' + document.get('url')

            templateData.d = (content) ->
                if content?
                    document = @getDocument()
                    S = require('string')
                    return S(content).replaceAll('@d', document.get('ptr')).s
            @

        extendCollections: (opts) ->
            # Prepare
            config = @getConfig()
            docpad = @docpad
            domainNames = config.domains.map (domain) -> domain.name

            for collection in docpad.collections
                if collection.options.name
                    for domainName in domainNames
                        domainCollectionName = collection.options.name + '.' + domainName
                        domainCollection = collection.findAllLive(relativeOutPath: $startsWith: domainName)
                        docpad.setCollection domainCollectionName, domainCollection


        renderBeforePriority: 560
        renderBefore: (opts,next) ->
            # Prepare
            docpad = @docpad
            config = @getConfig()
            {collection,templateData} = opts
            documents = docpad.getCollection('documents')
            files = docpad.getCollection('files')
                       
            domainNames = config.domains.map (domain) -> domain.name
            docpad.domainMap = {}
            docpad.domainMap['default'] = {}

            path = require('path')
            S = require('string')

            documents.forEach (document) ->
                sections = document.get('relativeOutPath').split(path.sep)
                documentDomain = undefined
                if sections[0] in domainNames
                    depth = sections.length - 1
                    documentDomain = (config.domains.filter (domain) -> domain.name is sections[0])[0]
                    document.set('domainName', documentDomain.name)
                    document.set('domain', documentDomain)
                else
                    depth = sections.length;

                pathToRoot = ['.']
                if depth > 1 
                    pathToRoot.push('..') for i in [0..depth-2]
                ptr = pathToRoot.join('/')
                document.set('ptr', ptr)
                absoluteDomainPath = S(document.get('relativeOutPath')).replaceAll(path.sep,'/')
                if documentDomain?
                    absoluteDomainPath = absoluteDomainPath.replace(documentDomain.name + '/','')
                document.set('absoluteDomainPath', '/' + absoluteDomainPath)
                if not document.get('domain')?
                    document.set('replicate', true)

                rel = document.get('rel')
                parent = document.get('parent')
                if rel?
                    if not parent?
                        idx = rel.lastIndexOf('/')
                        parent = S(rel).left(idx)
                        if S(parent).isEmpty()
                            parent = '/home'
                        parent = parent.toString()
                        if rel is '/home'
                            parent = undefined
                        document.set('parent', parent)
                    if not document.get('isPagedAuto')
                        domainName = document.get('domainName')
                        domainName ?= 'default'
                        docpad.domainMap[domainName] ?= {}
                        docpad.domainMap[domainName][rel] = document

            files.forEach (file) ->
                sections = file.get('relativeOutPath').split(path.sep)
                documentDomain = undefined
                if sections[0] in domainNames
                    documentDomain = (config.domains.filter (domain) -> domain.name is sections[0])[0]
                    file.set('domainName', documentDomain.name)
                    file.set('domain', documentDomain)
                    
            next?()

        generateAfterPriority: 400
        generateAfter: (opts, next) ->
            docpad = @docpad
            config = @config
            config.firstRun ?= true
            {collection,templateData} = opts
            domainNames = config.domains.map (domain) -> domain.name

            console.log 'Domain replication'
            collection.forEach (item)->
                console.log item.get('relativeOutPath')
            
            fs = require('fs-extra')
            path = require('path')
            S = require('string')

            copyFileToDomain = (absolutePath, absoluteDomainPath, domainName, referenceFile) ->
                sourceFile = path.join(docpad.config.outPath, absolutePath)
                destinationFile = path.join(docpad.config.outPath, domainName, absoluteDomainPath)
                copy = false
                try
                    sourceStats = fs.statSync(sourceFile)
                    sourceSize = sourceStats.size
                    if referenceFile?
                        sourceStats = fs.statSync(referenceFile)                        
                    destinationStats = fs.statSync(destinationFile)

                    if (not config.firstRun? and collection.findOne(relativeOutPath: absolutePath)?) or destinationStats.mtime < sourceStats.mtime or destinationStats.size != sourceSize
                        fs.removeSync(destinationFile)
                        copy = true
                catch err
                    copy = true

                if copy
                    docpad.log 'info', 'Replicating ' + path.join(domainName, absoluteDomainPath)
                    try
                        if fs.existsSync sourceFile
                            fs.copySync(sourceFile,destinationFile)
                        else
                            docpad.log 'error', 'Error replicating ' + sourceFile + ' to ' + destinationFile
                    catch err
                        docpad.log 'warn', 'Error replicating ' + sourceFile + ' to ' + destinationFile
                        docpad.log 'warn', err

            copyFileToDomains = (globalFile) ->
                relativeOutPath = globalFile.get('relativeOutPath')
                if not globalFile.get('domainName')? and not globalFile.get('notInDomain')
                    for domainName in domainNames when docpad.domainMap[domainName]?
                        copyFileToDomain(relativeOutPath, relativeOutPath, domainName, globalFile.get('fullPath'))

            documents = docpad.getCollection('documents')
            documents.forEach (document) ->
                if document.get('replicate')
                    copyFileToDomains document

            files = docpad.getCollection('files')
            files.forEach (file) ->
                copyFileToDomains file

            for file in config.files
                copyFileToDomain(file.absolutePath, file.absoluteDomainPath, file.domainName)
            config.files = []

            config.firstRun = false
            
            next?()

        writeAfter: (opts, next) ->
            console.log 'Domain write after'
            next?()
