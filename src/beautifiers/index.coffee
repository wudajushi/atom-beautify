_ = require('lodash')
_plus = require('underscore-plus')
Promise = require('bluebird')
Languages = require('../languages/')
path = require('path')

# Lazy loaded dependencies
extend = null
Analytics = null
fs = null
strip = null
yaml = null
editorconfig = null

# Misc
{allowUnsafeEval} = require 'loophole'
allowUnsafeEval ->
  Analytics = require("analytics-node")
pkg = require("../../package.json")
# Analytics
analyticsWriteKey = "u3c26xkae8"

###
Register all supported beautifiers
###
module.exports = class Beautifiers

    ###
    List of beautifier names

    To register a beautifier add it's name here
    ###
    beautifierNames: [
        'uncrustify'
        'autopep8'
        'coffee-formatter'
        'htmlbeautifier'
        'js-beautify'
        'perltidy'
        'php-cs-fixer'
        'prettydiff'
        'ruby-beautify'
        'sqlformat'
        'tidy-markdown'
        'typescript-formatter'
    ]

    ###
    List of loaded beautifiers

    Autogenerated in `constructor` from `beautifierNames`
    ###
    beautifiers: null

    ###
    All beautifier options

    Autogenerated in `constructor`
    ###
    options: null

    ###
    Languages
    ###
    languages: new Languages()

    ###
    Constructor
    ###
    constructor: ->
        # Load beautifiers
        @beautifiers = _.map(@beautifierNames, (name) ->
            Beautifier = require("./#{name}")
            new Beautifier()
        )
        # Build options from @beautifiers and @languages
        @options = @buildOptionsForBeautifiers(@beautifiers)

    ###

    ###
    buildOptionsForBeautifiers: (beautifiers) ->
        # Get all Options for Languages
        langOptions = {}
        languages = {} # Hash map of languages with their names
        for lang in @languages.languages
            langOptions[lang.name] ?= {}
            languages[lang.name] ?= lang
            options = langOptions[lang.name]
            # Init field for supported beautifiers
            lang.beautifiers = []
            # Process all language options
            for field, op of lang.options
                if not op.title?
                    op.title = _plus.uncamelcase(field).split('.')
                                    .map(_plus.capitalize).join(' ')
                op.title = "#{lang.name} - #{op.title}"
                # Init field for supported beautifiers
                op.beautifiers = []
                # Add option
                options[field] = op

        # Find supported beautifiers for each language
        for beautifier in beautifiers
            beautifierName = beautifier.name
            # Iterate over supported languages
            for languageName, options of beautifier.options
                laOp = langOptions[languageName]
                # Is a valid Language name
                if typeof options is "boolean"
                    # Enable / disable all options
                    if options is true
                        # Beautifier supports all options for this language
                        if laOp
                            # console.log('add supported beautifier', languageName, beautifierName)
                            languages[languageName]?.beautifiers.push(beautifierName)
                            for field, op of laOp
                                op.beautifiers.push(beautifierName)
                        else
                            console.warn("Could not find options for language: #{languageName}")
                else if typeof options is "object"
                    # Iterate over beautifier's options for this language
                    for field, op of options
                        if typeof op is "boolean"
                            # Transformation
                            if op is true
                                languages[languageName]?.beautifiers.push(beautifierName)
                                laOp?[field]?.beautifiers.push(beautifierName)
                        else if typeof op is "string"
                            # Rename
                            # console.log('support option with rename:', field, op, languageName, beautifierName, langOptions)
                            languages[languageName]?.beautifiers.push(beautifierName)
                            laOp?[op]?.beautifiers.push(beautifierName)
                        else if typeof op is "function"
                            # Transformation
                            languages[languageName]?.beautifiers.push(beautifierName)
                            laOp?[field]?.beautifiers.push(beautifierName)
                        else if _.isArray(op)
                            # Complex Function
                            [fields..., fn] = op
                            # Add beautifier support to all required fields
                            languages[languageName]?.beautifiers.push(beautifierName)
                            for f in fields
                                # Add beautifier to required field
                                laOp?[f]?.beautifiers.push(beautifierName)
                        else
                            # Unsupported
                            console.warn("Unsupported option:", beautifierName, languageName, field, op, langOptions)

        # Prefix language's options with namespace
        for langName, ops of langOptions
            # Get language with name
            lang = languages[langName]
            # Use the namespace from language as key prefix
            prefix = lang.namespace
            # console.log(langName, lang, prefix, ops)
            # Iterate over all language options and rename fields
            for field, op of ops
                # Rename field
                delete ops[field]
                ops["#{prefix}_#{field}"] = op

        # Flatten Options per language to array of all options
        allOptions = _.values(langOptions)
        # console.log('allOptions', allOptions)
        # Flatten array of objects to single object for options
        flatOptions = _.reduce(allOptions, ((result, languageOptions, language) ->
            # Iterate over fields (keys) in Language's Options
            # and merge them into single result
            # console.log('language options', language, languageOptions, result)
            return _.reduce(languageOptions, ((result, optionDef, optionName) ->
                # TODO: Add supported beautifiers to option description
                # console.log('optionDef', optionDef, optionName)
                if optionDef.beautifiers.length > 0
                    # optionDef.title = "#{optionDef.title} - Supported by #{optionDef.beautifiers.join(', ')}"
                    optionDef.description = "#{optionDef.description} (Supported by #{optionDef.beautifiers.join(', ')})"
                else
                    # optionDef.title = "(DEPRECATED) #{optionDef.title}"
                    optionDef.description = "#{optionDef.description} (Not supported by any beautifiers)"
                if result[optionName]?
                    console.warn("Duplicate option detected: ", optionName, optionDef)
                result[optionName] = optionDef
                return result
            ), result)
        ), {})

        # Generate Language configurations
        langConfigs = {}
        # Process all languages
        for langName, lang of languages
            name = lang.name
            beautifiers = lang.beautifiers
            langConfigs[name] = {
                type: 'object'
                properties:
                    disabled:
                        title: "Language Config - #{name} - Disable Beautifying Language"
                        type: 'boolean'
                        default: false
                        description: "Disable #{name} Beautification"
                    default_beautifier:
                        title: "Language Config - #{name} - Default Beautifier"
                        type: 'string'
                        default: beautifiers[0]
                        description: "Default Beautifier to be used for #{name}"
                        enum: _.uniq(beautifiers)
            }
        # Add Language configurations
        flatOptions.languages = {
              type: 'object'
              properties: langConfigs
        }

        return flatOptions

    ###

    ###
    getBeautifiers: (language, options) ->
        # console.log(@beautifiers)
        _.filter(@beautifiers, (beautifier) ->
            # console.log('beautifier',beautifier, language)
            _.contains(beautifier.languages, language)
        )

    beautify: (text, allOptions, grammar, filePath) ->
        return new Promise((resolve, reject) =>

            # Get language
            fileExtension = path.extname(filePath)
            languages = @languages.getLanguages({grammar, fileExtension})

            # Check if unsupported language
            if languages.length < 1
                unsupportedGrammar = true
            else
                # TODO: select appropriate language
                language = languages[0]

                # Get language config
                langConfig = atom.config.get("atom-beautify.languages")?[language.name]

                # Beautify!
                unsupportedGrammar = false
                # Check if Language is disabled
                if langConfig?.disabled
                  return resolve(null)

                # Options for Language
                options = @getOptions(language.namespace, allOptions) || {}
                # Support fallback for options
                if language.fallback?
                    for fallback in language.fallback
                        # Merge current options on top of fallback options
                        options = _.merge(@getOptions(fallback, allOptions) || {}, options)

                # Get Beautifier
                # console.log(grammar, language)
                beautifiers = @getBeautifiers(language.name, options)
                # console.log('beautifiers', beautifiers)

                # Check if unsupported language
                if beautifiers.length < 1
                    unsupportedGrammar = true
                else
                    # Select beautifier from language config preferences
                    preferredBeautifierName = langConfig.default_beautifier
                    beautifier = _.find(beautifiers, (beautifier) ->
                        beautifier.name is preferredBeautifierName
                    ) or beautifiers[0]
                    # console.log('beautifier', beautifier.name, beautifiers)

                    transformOptions = (beautifier, languageName, options) ->
                        # Transform options, if applicable
                        beautifierOptions = beautifier.options[languageName]
                        if typeof beautifierOptions is "boolean"
                            if beautifierOptions isnt true
                                # Disable options
                                options = {}
                        else if typeof beautifierOptions is "object"
                            # Transform the options
                            transformedOptions = {}
                            # Transform for fields
                            for field, op of beautifierOptions
                                if typeof op is "string"
                                    # Rename
                                    transformedOptions[field] = options[op]
                                else if typeof op is "function"
                                    # Transform
                                    transformedOptions[field] = op(options[field])
                                else if typeof op is "boolean"
                                    # Enable/Disable
                                    if op is true
                                        transformedOptions[field] = options[field]
                                else if _.isArray(op)
                                    # Complex function
                                    [fields..., fn] = op
                                    vals = _.map(fields, (f) ->
                                        return options[f]
                                    )
                                    # Apply function
                                    transformedOptions[field] = fn.apply(null, vals)

                            # Replace old options with new transformed options
                            options = transformedOptions
                        else
                            console.warn("Unsupported Language options: ", beautifierOptions)
                        return options

                    # Apply language-specific option transformations
                    options = transformOptions(beautifier, language.name, options)

                    # Beautify text with language options
                    beautifier.beautify(text, language.name, options)
                    .then(resolve)
                    .catch(reject)

            # Check if Analytics is enabled
            if atom.config.get("atom-beautify.analytics")
              # Setup Analytics
              analytics = new Analytics(analyticsWriteKey)
              unless atom.config.get("atom-beautify._analyticsUserId")
                uuid = require("node-uuid")
                atom.config.set "atom-beautify._analyticsUserId", uuid.v4()
              # Setup Analytics User Id
              userId = atom.config.get("atom-beautify._analyticsUserId")
              analytics.identify userId: userId
              version = pkg.version
              analytics.track
                userId: atom.config.get("atom-beautify._analyticsUserId")
                event: "Beautify"
                properties:
                  language: language.name
                  grammar: grammar
                  extension: fileExtension
                  version: version
                  options: allOptions
                  label: language.name
                  category: version
            #
            if unsupportedGrammar
              if atom.config.get("atom-beautify.muteUnsupportedLanguageErrors")
                return resolve(null)
              else
                reject(new Error("Unsupported language for grammar '#{grammar}' with extension '#{fileExtension}'."))

        )

    findFileResults: {}

    # CLI
    getUserHome: ->
      process.env.HOME or process.env.HOMEPATH or process.env.USERPROFILE

    verifyExists: (fullPath) ->
      fs ?= require("fs")
      (if fs.existsSync(fullPath) then fullPath else null)

    # Storage for memoized results from find file
    # Should prevent lots of directory traversal &
    # lookups when liniting an entire project

    ###
    Searches for a file with a specified name starting with
    'dir' and going all the way up either until it finds the file
    or hits the root.

    @param {string} name filename to search for (e.g. .jshintrc)
    @param {string} dir directory to start search from (default:
    current working directory)
    @param {boolean} upwards should recurse upwards on failure? (default: true)

    @returns {string} normalized filename
    ###
    findFile: (name, dir, upwards=true) ->
      path ?= require("path")
      dir = dir or process.cwd()
      filename = path.normalize(path.join(dir, name))
      return @findFileResults[filename] if @findFileResults[filename] isnt `undefined`
      parent = path.resolve(dir, "../")
      if @verifyExists(filename)
        @findFileResults[filename] = filename
        return filename
      if dir is parent
        @findFileResults[filename] = null
        return null
      if upwards
        findFile name, parent
      else
        return null

    ###
    Tries to find a configuration file in either project directory
    or in the home directory. Configuration files are named
    '.jsbeautifyrc'.

    @param {string} config name of the configuration file
    @param {string} file path to the file to be linted
    @param {boolean} upwards should recurse upwards on failure? (default: true)

    @returns {string} a path to the config file
    ###
    findConfig: (config, file, upwards=true) ->
      path ?= require("path")
      dir = path.dirname(path.resolve(file))
      envs = @getUserHome()
      home = path.normalize(path.join(envs, config))
      proj = @findFile(config, dir, upwards)
      return proj if proj
      return home if @verifyExists(home)
      null
    getConfigOptionsFromSettings: (langs) ->
      config = atom.config.get('atom-beautify')
      options = {}
      # console.log(langs, config);
      # Iterate over keys of the settings
      _.every _.keys(config), (k) ->
        # Check if keys start with a language
        p = k.split("_")[0]
        idx = _.indexOf(langs, p)
        # console.log(k, p, idx);
        if idx >= 0
          # Remove the language prefix and nest in options
          lang = langs[idx]
          opt = k.replace(new RegExp("^" + lang + "_"), "")
          options[lang] = options[lang] or {}
          options[lang][opt] = config[k]
          # console.log(lang, opt);
        true
      # console.log(options);
      options


    # Look for .jsbeautifierrc in file and home path, check env variables
    getConfig: (startPath, upwards=true) ->
      # Verify that startPath is a string
      startPath = (if (typeof startPath is "string") then startPath else "")
      return {} unless startPath
      # Get the path to the config file
      configPath = @findConfig(".jsbeautifyrc", startPath, upwards)
      externalOptions = undefined
      if configPath
        fs ?= require("fs")
        contents = fs.readFileSync(configPath,
          encoding: "utf8"
        )
        unless contents
          externalOptions = {}
        else
          try
            strip ?= require("strip-json-comments")
            externalOptions = JSON.parse(strip(contents))
          catch e
            # console.log "Failed parsing config as JSON: " + configPath
            # Attempt as YAML
            try
              yaml ?= require("yaml-front-matter")
              externalOptions = yaml.safeLoad(contents)
            catch e
              console.log "Failed parsing config as YAML and JSON: " + configPath
              externalOptions = {}
      else
        externalOptions = {}
      externalOptions

    getOptionsForPath: (editedFilePath, editor) ->
      languageNamespaces = @languages.namespaces

      # Editor Options
      editorOptions = {}
      if editor?
        # Get current Atom editor configuration
        isSelection = !!editor.getSelectedText()
        softTabs = editor.softTabs
        tabLength = editor.getTabLength()
        editorOptions =
          indent_size: (if softTabs then tabLength else 1)
          indent_char: (if softTabs then " " else "\t")
          indent_with_tabs: not softTabs

      # From Package Settings
      configOptions = @getConfigOptionsFromSettings(languageNamespaces)

      # Get configuration in User's Home directory
      userHome = @getUserHome()
      # FAKEFILENAME forces `path` to treat as file path and it's parent directory
      # is the userHome. See implementation of findConfig
      # and how path.dirname(DIRECTORY) returns the parent directory of DIRECTORY
      homeOptions = @getConfig(path.join(userHome,"FAKEFILENAME"), false)

      if editedFilePath?
        # Handle EditorConfig options
        # http://editorconfig.org/
        editorconfig ?= require('editorconfig');
        editorConfigOptions = editorconfig.parse(editedFilePath);
        # Transform EditorConfig to Atom Beautify's config structure and naming
        if editorConfigOptions.indent_style is 'space'
          editorConfigOptions.indent_char = " "
          # if (editorConfigOptions.indent_size)
          #   editorConfigOptions.indent_size = config.indent_size
        else if editorConfigOptions.indent_style is 'tab'
          editorConfigOptions.indent_char = "\t"
          editorConfigOptions.indent_with_tabs = true
          if (editorConfigOptions.tab_width)
              editorConfigOptions.indent_size = editorConfigOptions.tab_width

        # Get all options in configuration files from this directory upwards to root
        projectOptions = []
        p = path.dirname(editedFilePath)
        # Check if p is root (top directory)
        while p isnt path.resolve(p,"../")
          # Get config for p
          pf = path.join(p, "FAKEFILENAME")
          pc = @getConfig(pf, false)
          # Add config for p to project's config options
          projectOptions.push(pc)
          # console.log p, pc
          # Move upwards
          p = path.resolve(p,"../")
      else
        editorConfigOptions = {}
        projectOptions = []

      # Combine all options together
      allOptions = [
        editorOptions
        configOptions
        homeOptions
        editorConfigOptions
      ]
      allOptions = allOptions.concat(projectOptions)
      # console.log(allOptions)
      return allOptions

    getOptions: (selection, allOptions) ->
        self = this
        _ ?= require("lodash")
        extend ?= require("extend")
        # console.log(selection, allOptions);
        # Reduce all options into correctly merged options.
        options = _.reduce(allOptions, (result, currOptions) ->
          containsNested = false
          collectedConfig = {}
          key = undefined
          # Check to see if config file uses nested object format to split up js/css/html options
          for key of currOptions
            # Check if is supported language
            if _.indexOf(self.languages.namespaces, key) >= 0 and typeof currOptions[key] is "object" # Check if nested object (more options in value)
              containsNested = true
              break # Found, break out of loop, no need to continue
          # console.log(containsNested, currOptions);
          # Create a flat object of config options if nested format was used
          unless containsNested
            _.merge collectedConfig, currOptions
          else
            # Merge with selected options
            # where `selection` could be `html`, `js`, 'css', etc
            # console.log(selection, currOptions[selection]);
            _.merge collectedConfig, currOptions[selection]
          extend result, collectedConfig
        , {} )
        # TODO: Clean.
        # There is a bug in nopt
        # See https://github.com/npm/nopt/issues/38#issuecomment-45971505
        # console.log('pre-clean', JSON.stringify(options));
        #options = cleanOptions(options, knownOpts);
        #console.log('post-clean', JSON.stringify(options));
        options