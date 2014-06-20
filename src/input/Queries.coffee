# - Listens for changes in DOM,
# - Invalidates cached DOM Queries
#   by bruteforcing combinators on reachable elements

# Input:  MutationEvent, processes observed mutations
# Output: Expressions, revaluates expressions

# State:  - `@[path]`: elements and collections by selector path
#         - `@_watchers[id]`: dom queries by element id 

class Queries
  options:
    subtree: true
    childList: true
    attributes: true
    characterData: true
    attributeOldValue: true

  Observer: 
    window.MutationObserver || window.WebKitMutationObserver || window.JsMutationObserver

  constructor: (@engine, @output) ->
    @_watchers = {}
    @references = @engine.references
    @listener = new @Observer @read.bind(this)
    @listener.observe @engine.scope, @options 

  # Re-evaluate updated queries
  # Watchers are stored in a single array in groups of 3 properties
  write: (queries) ->
    for query, index in queries by 3
      continuation = queries[index + 1]
      scope = queries[index + 2]
      @output.read query, continuation, scope
    @
    
  # Listen to changes in DOM to broadcast them all around
  read: (mutations) ->
    queries = []
    scope = @engine.scope
    for mutation in mutations
      target = parent = mutation.target
      switch mutation.type
        when "attributes"
          # Notify parents about class and attribute changes
          if mutation.attributeName == 'class'
            klasses = parent.classList
            old = mutation.oldValue.split(' ')
            changed = []
            for kls in old
              changed.push kls unless kls && klasses.contains(kls)
            for kls in klasses
              changed.push kls unless kls && old.indexOf(kls) > -1
            while parent.nodeType == 1
              for kls in changed
                @match(queries, parent, '$class', kls, target)
              break if parent == scope
              parent = parent.parentNode
            parent = target

          while parent.nodeType == 1
            @match(queries, parent, '$attribute', mutation.attributeName, target)
            break if parent == scope
            parent = parent.parentNode

        when "childList"
          # Invalidate sibling observers
          changed = []
          for child in mutation.addedNodes
            if child.nodeType == 1
              changed.push(child)
          for child in mutation.removedNodes
            if child.nodeType == 1
              changed.push(child)
          prev = next = mutation
          firstPrev = firstNext = true
          while (prev = prev.previousSibling)
            if prev.nodeType == 1
              if firstPrev
                @match(queries, prev, '+') 
                @match(queries, prev, '++')
                firstPrev = false
              @match(queries, prev, '~', undefined, changed)
              @match(queries, prev, '~~', undefined, changed)
          while (next = next.nextSibling)
            if next.nodeType == 1
              if firstNext
                @match(queries, next, '!+') 
                @match(queries, next, '++')
                firstNext = false
              @match(queries, next, '!~', undefined, changed)
              @match(queries, next, '~~', undefined, changed)


          # Invalidate descendants observers
          @match(queries, parent, '>', undefined, changed)
          allChanged = []

          for child in changed
            @match(queries, child, '!>', undefined, parent)
            allChanged.push(child)
            allChanged.push.apply(allChanged, undefined, child.getElementsByTagName('*'))

          while parent && parent.nodeType == 1
            @match(queries, parent, ' ', undefined, allChanged)

            for child in allChanged
              prev = child
              while prev = prev.previousSibling
                if prev.nodeType == 1
                  @match(queries, parent, ' +', undefined, prev)
                  break
              @match(queries, parent, ' +', undefined, child)
              @match(queries, child, '!', undefined, parent)
            parent = parent.parentNode

    # Return possibly updated queries
    if queries.length
      this.write(queries)

    return true

  # Manually add element to collection
  add: (node, continuation) ->
    collection = @[continuation] ||= []
    if collection.indexOf(node) == -1
      collection.push(node)
    else
      (collection.dupes ||= []).push(node)
    return collection

  # HOOK: Remove observers and cached node lists
  remove: (id, continuation) ->
    # Detach observer and its subquery when cleaning by id
    if watchers = @_watchers[id]
      ref = continuation + id
      index = 0
      while watcher = watchers[index]
        contd = watchers[index + 1]
        unless contd == ref
          index += 3
          continue
        watchers.splice(index, 3)
        path = (contd || '') + watcher.key
        @clean(path)
      delete @_watchers[id] unless watchers.length
    # Remove cached DOM query
    else 
      @clean(id)
    @

  clean: (path) ->
    if result = @[path]
      delete @[path]
      if result.length != undefined
        @engine.context.remove child, path, result for child in result
      else
        @engine.context.remove result, path
    return true

  # Filter out known nodes from DOM collections
  filter: (node, args, result, operation, continuation, scope) ->
    return if result == old
    node ||= scope || args[0]
    path = (continuation || '') + operation.key
    old = @[path]
    isCollection = result && result.length != undefined
    
    # Subscribe context to the query
    if id = @references.identify(node)
      watchers = @_watchers[id] ||= []
      if watchers.indexOf(operation) == -1
        watchers.push(operation, continuation, node)
    
    # Clean refs of nodes that dont match anymore
    if old && old.length
      removed = undefined
      for child in old
        if !result || old.indexOf.call(result, child) == -1
          @engine.context.remove child, path, old
          (removed ||= []).push child
      if continuation && (!isCollection || !result.length)
        @engine.context.remove path, continuation

    # Register newly found nodes
    if isCollection
      added = undefined
      for child in result
        if !old || watchers.indexOf.call(old, child) == -1  
          (added ||= []).push child if old

      if continuation && (!old || !old.length)
        @references.append continuation, path

      # Snapshot live node list for future reference
      if result && result.item && (!old || removed || added)
        result = watchers.slice.call(result, 0)
    else if result != undefined || old != undefined
      @references.append continuation, path

    @[path] = result
    if result
      console.log('found', result.nodeType == 1 && 1 || result.length, ' by' ,path)
    return if removed && !added
    return added || result

  # Check if a node observes this qualifier or combinator
  match: (queries, node, group, qualifier, changed) ->
    return unless id = node._gss_id
    return unless watchers = @_watchers[id]
    for operation, index in watchers by 3
      if groupped = operation[group]
        continuation = watchers[index + 1]
        scope = watchers[index + 2]
        if qualifier
          @qualify(queries, operation, continuation, scope, groupped, qualifier)
        else if changed.nodeType
          @qualify(queries, operation, continuation, scope, groupped, changed.tagName, '*')
        else for change in changed
          @qualify(queries, operation, continuation, scope, groupped, change.tagName, '*')
    @

  # Check if query observes qualifier by combinator 
  qualify: (queries, operation, continuation, scope, groupped, qualifier, fallback) ->
    if typeof scope == 'string'
      debugger
    if (indexed = groupped[qualifier]) || (fallback && groupped[fallback])
      if queries.indexOf(operation) == -1
        queries.push(operation, continuation, scope)
    @

module.exports = Queries