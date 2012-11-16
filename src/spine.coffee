
# ## Events
# An object that provides event usage.
# If you extend events you will be given access to binding and calling events.
Events =

  # Bind the event name (String) to a callback (Function)
  bind: (ev, callback) ->
    evs   = ev.split(' ')
    calls = @hasOwnProperty('_callbacks') and @_callbacks or= {}

    for name in evs
      calls[name] or= []
      calls[name].push(callback)
    this

  # A one time binding that will detatch itself after the first time it is called.
  one: (ev, callback) ->
    @bind ev, ->
      @unbind(ev, arguments.callee)
      callback.apply(this, arguments)

  # Trigger a specific event. The first argument will be the event name followed by
  # a series of values you wish to pass to any bound callbacks
  #
  #     @bind('refresh', function(a,b){})
  #     @trigger('refresh', 1, 2)
  #
  #  will call the anonymous fuctoin with a=1, b=2
  trigger: (args...) ->
    ev = args.shift()

    list = @hasOwnProperty('_callbacks') and @_callbacks?[ev]
    return unless list

    for callback in list
      if callback.apply(this, args) is false
        break
    true

  # Unbind will look for a matching event and callback paring and detatch them.
  unbind: (ev, callback) ->
    unless ev
      @_callbacks = {}
      return this

    list = @_callbacks?[ev]
    return this unless list

    unless callback
      delete @_callbacks[ev]
      return this

    for cb, i in list when cb is callback
      list = list.slice()
      list.splice(i, 1)
      @_callbacks[ev] = list
      break
    this

# ## Log
# An object that provides logging functionality.
# It looks for the availablility of console.log and will not error if unavailable.
# When mixed into classes the logPrefix can be overridden to provide context for the log messages.
Log =
  trace: true

  logPrefix: '(App)'

  log: (args...) ->
    return unless @trace
    if @logPrefix then args.unshift(@logPrefix)
    console?.log?(args...)
    this

moduleKeywords = ['included', 'extended']

# ## Module
# A base module providing internal *include* and *extend* support along with JavaScript scope
# altering proxy methods.
class Module

  # Provides a mechanism for copying in functionality from the provided object to the
  # current object. This builds functionality *into the prototype* of the current class.
  @include: (obj) ->
    throw new Error('include(obj) requires obj') unless obj
    for key, value of obj when key not in moduleKeywords
      @::[key] = value
    obj.included?.apply(this)
    this

  # Provides a mechanism for copying in functionality from the provided object to the
  # current object. This builds functionality *into the instance* of the current class.
  @extend: (obj) ->
    throw new Error('extend(obj) requires obj') unless obj
    for key, value of obj when key not in moduleKeywords
      @[key] = value
    obj.extended?.apply(this)
    this

  # Provides a mechanism for forcing scope. Using a closure any provided function will be
  # called with the 'this' scope set to the instance of the current class. Good to avoid issues
  # such as DOM events setting the scope to window.
  @proxy: (func) ->
    => func.apply(this, arguments)

  # Instance representation of the class level 'proxy' method.
  proxy: (func) ->
    => func.apply(this, arguments)

  constructor: ->
    @init?(arguments...)

# ## Model
# Provides the base class that all *models* are to extend from.
class Model extends Module
  @extend Events

  @records: {}
  @crecords: {}
  @attributes: []

  # Class method for defining how a model should exist.
  # The first *name* argument is the internal representation and the remaining
  # arguments describe the expected internal attributes.
  @configure: (name, attributes...) ->
    @className  = name
    @records    = {}
    @crecords   = {}
    @attributes = attributes if attributes.length
    @attributes and= makeArray(@attributes)
    @attributes or=  []
    @unbind()
    this

  # Class method describing model name and attributes
  @toString: -> "#{@className}(#{@attributes.join(", ")})"

  # Finder method that will find a model record based on it's ID.
  # _Note - this will attempt a direct ID match and then a clientside (CID) match.
  @find: (id) ->
    record = @records[id]
    if !record and ("#{id}").match(/c-\d+/)
      return @findCID(id)
    throw new Error('Unknown record') unless record
    record.clone()

  # Finder method that will use the client side ID for matching.
  @findCID: (cid) ->
    record = @crecords[cid]
    throw new Error('Unknown record') unless record
    record.clone()

  # Helper returning a record if it is found or false if not
  @exists: (id) ->
    try
      return @find(id)
    catch e
      return false

  # Class method for refreshing a models data content using the values argument.
  # If the options argument has the value clear set to true it will first remove all records.
  # The event *refresh* is triggered on the model after the model records have been built.
  @refresh: (values, options = {}) ->
    if options.clear
      @records  = {}
      @crecords = {}

    records = @fromJSON(values)
    records = [records] unless isArray(records)

    for record in records
      record.id           or= record.cid
      @records[record.id]   = record
      @crecords[record.cid] = record

    @trigger('refresh', @cloneArray(records))
    this

  # Selectes a portion of model records using a callback to determine which. The callback should
  # return true or false based on the individual record being tested.
  @select: (callback) ->
    result = (record for id, record of @records when callback(record))
    @cloneArray(result)

  # Finds the firswt matching model record where the argument *name* (which is the attribute name) matches the
  # provided *value* argument.
  @findByAttribute: (name, value) ->
    for id, record of @records
      if record[name] is value
        return record.clone()
    null

  # Finds all model records where the argument *name* (which is the attribute name) matches the
  # provided *value* argument.
  @findAllByAttribute: (name, value) ->
    @select (item) ->
      item[name] is value

  # Helper method for looping over all model records applying the provided calback function to each record.
  @each: (callback) ->
    for key, value of @records
      callback(value.clone())

  # Helper method that provides all model records.
  @all: ->
    @cloneArray(@recordsValues())

  # Helper method that provides the first model record.
  @first: ->
    record = @recordsValues()[0]
    record?.clone()

  # Helper method that provides the last model record.
  @last: ->
    values = @recordsValues()
    record = values[values.length - 1]
    record?.clone()

  # Helper method that provides a numerical count of the total number of model records.
  @count: ->
    @recordsValues().length

  # Will delete all model records without callbacks
  @deleteAll: ->
    for key, value of @records
      delete @records[key]

  # Will delete all model records, applying the destroy callback on each record as it is removed.
  @destroyAll: ->
    for key, value of @records
      @records[key].destroy()

  # Will update a particular record noted by the *id* attribute
  @update: (id, atts, options) ->
    @find(id).updateAttributes(atts, options)

  # Create and save a new record with the passed attributes.
  # If options.validate is false the validation will be skipped.
  # If an error occurs the *error* event will be triggered.
  @create: (atts, options) ->
    record = new @(atts)
    record.save(options)

  # Call *destroy* on a model record found by the provided *id*.
  # The provided options will be passed to the *beforeDestroy*, *destroy* and *change* events.
  # The model will then be unbound from all events.
  @destroy: (id, options) ->
    @find(id).destroy(options)

  # A helper to bind the provided callback to the *change* event of this model or if
  # no callback is provided it will trigger the event.
  @change: (callbackOrParams) ->
    if typeof callbackOrParams is 'function'
      @bind('change', callbackOrParams)
    else
      @trigger('change', callbackOrParams)

  # A helper to bind the provided callback to the *fetch* event of this model or if
  # no callback is provided it will trigger the event.
  @fetch: (callbackOrParams) ->
    if typeof callbackOrParams is 'function'
      @bind('fetch', callbackOrParams)
    else
      @trigger('fetch', callbackOrParams)

  # Will conver all model records to JSON using the *recordValues* method.
  @toJSON: ->
    @recordsValues()

  # Will convert a passed *Array* of attribute hashes or *JSON String* into
  # an array of *unsaved model records*.
  @fromJSON: (objects) ->
    return unless objects
    if typeof objects is 'string'
      objects = JSON.parse(objects)
    if isArray(objects)
      (new @(value) for value in objects)
    else
      new @(objects)

  # Helper that will serialize the content of a form and create a new
  # model record using the values.
  @fromForm: ->
    (new this).fromForm(arguments...)

  # ## Private Methods

  # Build an array of the models based on the internal *records* array.
  @recordsValues: ->
    result = []
    for key, value of @records
      result.push(value)
    result

  # Create an array of model clones.
  @cloneArray: (array) ->
    (value.clone() for value in array)

  @idCounter: 0

  # Generate a uid
  @uid: (prefix = '') ->
    uid = prefix + @idCounter++
    uid = @uid(prefix) if @exists(uid)
    uid

  # ## Instance Methods

  # Taking an attributes object, return a new model record
  constructor: (atts) ->
    super
    @load atts if atts
    @cid = @constructor.uid('c-')

  # Determie if this model already exists in the collection using the id.
  # Will return false if no ID is provided.
  isNew: ->
    not @exists()

  # Helper for determining validity. If the validate method does
  # not return any issues the model is deemed valid.
  isValid: ->
    not @validate()

  # Stub for validation. _Override to provide actual validation._
  validate: ->

  # Load in an attribute object to the current model.
  # If the attribute *key* references a function internally it will pass it
  # the *value* as an argument, else it will assign the *value* as a property.
  load: (atts) ->
    for key, value of atts
      if typeof @[key] is 'function'
        @[key](value)
      else
        @[key] = value
    this

  # Using the initial list of attributes passed in via configure tis will return
  # an object with key / value pairs. If the attribute references a function, the value
  # will be the result of that function.
  attributes: ->
    result = {}
    for key in @constructor.attributes when key of this
      if typeof @[key] is 'function'
        result[key] = @[key]()
      else
        result[key] = @[key]
    result.id = @id if @id
    result

  # Using the constructor and ID or CID, determine if two model records match.
  eql: (rec) ->
    !!(rec and rec.constructor is @constructor and
        (rec.cid is @cid) or (rec.id and rec.id is @id))

  # Save the current model. If the options.validate is set to false, skip validation.
  # The *error* event will be triggered on validation errors and the *beforeSave* and
  # *save* events will be triggered during the save process.
  save: (options = {}) ->
    unless options.validate is false
      error = @validate()
      if error
        @trigger('error', error)
        return false

    @trigger('beforeSave', options)
    record = if @isNew() then @create(options) else @update(options)
    @trigger('save', options)
    record

  # Update the internal attribute denoted by *name* with the provided *value*
  # and then call *save* on the record.
  updateAttribute: (name, value, options) ->
    @[name] = value
    @save(options)

  # Update multiple attributes by loading in the *atts* values via the *load* method
  # and then calling *save* on the record.
  updateAttributes: (atts, options) ->
    @load(atts)
    @save(options)

  # Change the *id* of the current record. This will update the internal references to
  # the record that use the id. It will *save* the record as part of the process.
  changeID: (id) ->
    records = @constructor.records
    records[id] = records[@id]
    delete records[@id]
    @id = id
    @save()

  # Delete a record from all references / indexes and trigger events *beforeDestroy*,
  # *destroy* and *change* as part of the process. It will also unbind the record from
  # any linked callbacks and return the record itself at the end.
  destroy: (options = {}) ->
    @trigger('beforeDestroy', options)
    delete @constructor.records[@id]
    delete @constructor.crecords[@cid]
    @destroyed = true
    @trigger('destroy', options)
    @trigger('change', 'destroy', options)
    @unbind()
    this

  # Duplicate the current record into a *new unsaved record*. If the *newRecord*
  # argument is false, then the current client side ID is maintained between
  # records, else the CID and ID are blanked.
  dup: (newRecord) ->
    result = new @constructor(@attributes())
    if newRecord is false
      result.cid = @cid
    else
      delete result.id
    result

  # Create a clone of the current object which usese the current object
  # as the prototype for a new object allowing inheritance and overriding.
  clone: ->
    createObject(this)

  # Return the current instance of the object if it is unsaved else find
  # the record by it's id and reload the original attributes into this record.
  reload: ->
    return this if @isNew()
    original = @constructor.find(@id)
    @load(original.attributes())
    original

  # Return an attributes object from the current record.
  toJSON: ->
    @attributes()

  # Convert the current record into a string of class name and
  # serialized object.
  toString: ->
    "<#{@constructor.className} (#{JSON.stringify(this)})>"

  # Convert a form into an attributes object and use that to
  # initialise a new model record.
  fromForm: (form) ->
    result = {}
    for key in $(form).serializeArray()
      result[key.name] = key.value
    @load(result)

  # Return true if the current models ID is set and exists
  # in the current record set.
  exists: ->
    @id && @id of @constructor.records

  # ## Private Methods

  # Using the current model instances ID, update the model of matching ID in the main record set
  # with the current models attributes. This allows for non-destructive changing of models
  # prior to calling save. The action will trigger the events *beforeUpdate*, *update* and *change*.
  update: (options) ->
    @trigger('beforeUpdate', options)
    records = @constructor.records
    records[@id].load @attributes()
    clone = records[@id].clone()
    clone.trigger('update', options)
    clone.trigger('change', 'update', options)
    clone

  # Using the current model, create a new model record. The ID will be set to the current CID or the
  # ID if it is set. It will be a clone of the current model and trigger *beforeCreate*, *create* and
  # *change* events.
  create: (options) ->
    @trigger('beforeCreate', options)
    @id          = @cid unless @id

    record       = @dup(false)
    @constructor.records[@id]   = record
    @constructor.crecords[@cid] = record

    clone        = record.clone()
    clone.trigger('create', options)
    clone.trigger('change', 'create', options)
    clone

  # Bind the current model to the provided *events* array triggering the provided *callback* function.
  bind: (events, callback) ->
    @constructor.bind events, binder = (record) =>
      if record && @eql(record)
        callback.apply(this, arguments)
    @constructor.bind 'unbind', unbinder = (record) =>
      if record && @eql(record)
        @constructor.unbind(events, binder)
        @constructor.unbind('unbind', unbinder)
    binder

  one: (events, callback) ->
    binder = @bind events, =>
      @constructor.unbind(events, binder)
      callback.apply(this, arguments)

  trigger: (args...) ->
    args.splice(1, 0, this)
    @constructor.trigger(args...)

  unbind: ->
    @trigger('unbind')

class Controller extends Module
  @include Events
  @include Log

  eventSplitter: /^(\S+)\s*(.*)$/
  tag: 'div'

  constructor: (options) ->
    @options = options

    for key, value of @options
      @[key] = value

    @el  = document.createElement(@tag) unless @el
    @el  = $(@el)
    @$el = @el

    @el.addClass(@className) if @className
    @el.attr(@attributes) if @attributes

    @events = @constructor.events unless @events
    @elements = @constructor.elements unless @elements

    @delegateEvents(@events) if @events
    @refreshElements() if @elements

    super

  release: =>
    @trigger 'release'
    @el.remove()
    @unbind()

  $: (selector) -> $(selector, @el)

  delegateEvents: (events) ->
    for key, method of events

      if typeof(method) is 'function'
        # Always return true from event handlers
        method = do (method) => =>
          method.apply(this, arguments)
          true
      else
        unless @[method]
          throw new Error("#{method} doesn't exist")

        method = do (method) => =>
          @[method].apply(this, arguments)
          true

      match      = key.match(@eventSplitter)
      eventName  = match[1]
      selector   = match[2]

      if selector is ''
        @el.bind(eventName, method)
      else
        @el.delegate(selector, eventName, method)

  refreshElements: ->
    for key, value of @elements
      @[value] = @$(key)

  delay: (func, timeout) ->
    setTimeout(@proxy(func), timeout || 0)

  html: (element) ->
    @el.html(element.el or element)
    @refreshElements()
    @el

  append: (elements...) ->
    elements = (e.el or e for e in elements)
    @el.append(elements...)
    @refreshElements()
    @el

  appendTo: (element) ->
    @el.appendTo(element.el or element)
    @refreshElements()
    @el

  prepend: (elements...) ->
    elements = (e.el or e for e in elements)
    @el.prepend(elements...)
    @refreshElements()
    @el

  replace: (element) ->
    [previous, @el] = [@el, $(element.el or element)]
    previous.replaceWith(@el)
    @delegateEvents(@events)
    @refreshElements()
    @el

# Utilities & Shims

$ = window?.jQuery or window?.Zepto or (element) -> element

createObject = Object.create or (o) ->
  Func = ->
  Func.prototype = o
  new Func()

isArray = (value) ->
  Object::toString.call(value) is '[object Array]'

isBlank = (value) ->
  return true unless value
  return false for key of value
  true

makeArray = (args) ->
  Array::slice.call(args, 0)

# Globals

Spine = @Spine   = {}
module?.exports  = Spine

Spine.version    = '1.0.8'
Spine.isArray    = isArray
Spine.isBlank    = isBlank
Spine.$          = $
Spine.Events     = Events
Spine.Log        = Log
Spine.Module     = Module
Spine.Controller = Controller
Spine.Model      = Model

# Global events

Module.extend.call(Spine, Events)

# JavaScript compatability

Module.create = Module.sub =
  Controller.create = Controller.sub =
    Model.sub = (instances, statics) ->
      class Result extends this
      Result.include(instances) if instances
      Result.extend(statics) if statics
      Result.unbind?()
      Result

Model.setup = (name, attributes = []) ->
  class Instance extends this
  Instance.configure(name, attributes...)
  Instance

Spine.Class = Module
