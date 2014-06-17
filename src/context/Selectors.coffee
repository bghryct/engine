dummy = document.createElement('_')

class Selectors
  # Set up DOM observer and filter out old elements 
  onDOMQuery: (engine, scope, args, result, operation, continuation, subscope) ->
    return @engine.queries.filter(scope || operation.func && args[0], result, operation, continuation, subscope)

  remove: (id, continuation) ->
    if typeof id == 'object'
      id = @engine.references.recognize(id)
    @engine.queries.remove(id, continuation)
    # When removing id from collection
    if @engine.References::[id]
      path = continuation + id
      @engine.references.remove(continuation, path)
      # Output remove command for solver
      @engine.expressions.write(['remove', path], true)
    @

  # Selector commands

  '$query':
    group: '$query'
    1: "querySelectorAll"
    2: (node, value) ->
      return node if node.webkitMatchesSelector(value)
      
    # Create a shortcut operation to get through a group of operations
    perform: (object, operation) ->
      name = operation.def.group
      shortcut = [name, operation.promise]
      shortcut.parent = (operation.head || operation).parent
      shortcut.index = (operation.head || operation).index
      object.analyze(shortcut)
      tail = operation.tail
      global = tail.arity == 1 && tail.length == 2
      op = operation
      while op
        @analyze op, shortcut
        break if op == tail
        op = op[1]
      if (tail.parent == operation)
        unless global
          shortcut.splice(1, 0, tail[1])
      return shortcut


    # Walk through commands in selector to make a dictionary used by Observer
    analyze: (operation, parent) ->
      switch operation[0]
        when '$tag'
          if !parent || operation == operation.tail
            group = ' '
            index = (operation[2] || operation[1]).toUpperCase()
        when '$combinator'
          group = (parent && ' ' || '') +  operation.name
          index = operation.parent.name == "$tag" && operation.parent[2].toUpperCase() || "*"
        when '$class', '$pseudo', '$attribute'
          group = operation[0]
          index = operation[2] || operation[1]
      (((parent || operation)[group] ||= {})[index] ||= []).push operation
      index = group = null

    # Native selectors cant start with a non-space combinator or qualifier
    attempt: (operation) ->
      @analyze(operation) unless operation.name
      if operation.name == '$combinator'
        if group[group.skip] != ' '
          return false
      else if operation.arity == 2
        return false
      return true

  # Live collections

  '$class':
    prefix: '.'
    group: '$query'
    1: "getElementsByClassName"
    2: (node, value) ->
      return node if node.classList.contains(value)

  '$tag':
    prefix: ''
    group: '$query'
    1: "getElementsByTagName"
    2: (node, value) ->
      return node if value == '*' || node.tagName == value.toUpperCase()

  # DOM Lookups

  '$id':
    prefix: '#'
    group: '$query'
    1: "getElementById"
    2: (node, value) ->
      return node if node.id == name

  '$virtual':
    prefix: '"'
    suffix: '"'

  # Filters

  '$nth':
    prefix: ':nth('
    suffix: ')'
    command: (node, divisor, comparison) ->
      nodes = []
      for i, node in node
        if i % parseInt(divisor) == parseInt(comparison)
          nodes.push(nodes)
      return nodes


  # Commands that look up other commands
  
  '$attribute': 
    type: 'qualifier'
    prefix: '['
    suffix: ']'
    lookup: true

  '$pseudo': 
    type: 'qualifier'
    prefix: ':'
    lookup: true

  '$combinator':
    type: 'combinator'
    lookup: true

  '$reserved':
    type: 'combinator'
    prefix: '::'
    lookup: true
    
  # CSS Combinators with reversals

  ' ':
    group: '$query'
    1: (node) ->
      return node.getElementsByTagName("*")

  '!':
    1: (node) ->
      nodes = undefined
      while node = node.parentNode
        if node.nodeType == 1
          (nodes ||= []).push(node)
      return nodes

  '>':
    group: '$query'
    1: 
      if "children" in dummy 
        (node) -> 
          return node.children
      else 
        (node) ->
          child for child in node.childNodes when child.nodeType == 1

  '!>':
    1: 
      if dummy.hasOwnProperty("parentElement") 
        (node) ->
          return node.parentElement
      else
        (node) ->
          if parent = node.parentNode
            return parent if parent.nodeType == 1

  '+':
    group: '$query'
    1: 
      if dummy.hasOwnProperty("nextElementSibling")
        (node) ->
          return node.nextElementSibling
      else
        (node) ->
          while node = node.nextSibling
            return node if node.nodeType == 1

  '!+':
    1:
      if dummy.hasOwnProperty("previousElementSibling")
        (node) ->
          return node.previousElementSibling
      else
        (node) ->
          while node = node.previousSibling
            return node if node.nodeType == 1

  '++':
    1: (node) ->
      nodes = undefined
      while node = node.previousSibling
        if node.nodeType == 1
          (nodes ||= []).push(node)
          break
      while node = node.nextSibling
        if node.nodeType == 1
          (nodes ||= []).push(node)
          break
      return nodes;

  '~':
    group: '$query'
    1: (node) ->
      nodes = undefined
      while node = node.nextSibling
        (nodes ||= []).push(node) if node.nodeType == 1
      return nodes

  '!~':
    1: (node) ->
      nodes = undefined
      while node = node.previousSibling
        (nodes ||= []).push(node) if node.nodeType == 1
      return nodes
  
  '~~':
    1: (node) ->
      nodes = undefined
      while node = node.previousSibling
        (nodes ||= []).push(node) if node.nodeType == 1
      while node = node.nextSibling
        (nodes ||= []).push(node) if node.nodeType == 1
      return nodes

  # Pseudo classes

  ':value':
    1: (node) ->
      return node.value
    watch: "oninput"

  ':get':
    2: (node, property) ->
      return node[property]




  # Pseudo elements

  '::this':
    prefix: ''
    scoped: true
    1: (node) ->
      debugger
      return node

  '::parent':
    prefix: '::parent'
    scoped: true
    1: (node) ->
      if parent = node.parentNode
        if parent.nodeType == 1
          return parent

  '::scope':
    prefix: "::scope"
    1: (node) ->
      return @engine.scope

  '::window':
    prefix: 'window'
    absolute: "window"

# Set up custom trigger for all selector operations
# to filter out old elements from collections
for property, command of Selectors::
  if typeof command == 'object'
    command.callback = 'onDOMQuery'

module.exports = Selectors