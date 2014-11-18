Command = require('../concepts/Command')

class Condition extends Command
  type: 'Condition'
  
  signature: [
  	if: ['Query', 'Selector', 'Value', 'Constraint', 'Default'],
  	then: ['Any'], 
  	[
  		else: ['Any']
  	]
  ]

  cleaning: true

  domain: 'solved'

  update: (engine, operation, continuation, scope, ascender, ascending) ->

    watchers = engine.queries.watchers[scope._gss_id] ||= []
    if !watchers.length || engine.indexOfTriplet(watchers, operation.parent, continuation, scope) == -1
      watchers.push operation.parent, continuation, scope

    
    operation.parent.uid ||= '@' + (engine.queries.uid = (engine.queries.uid || 0) + 1)
    path = continuation + operation.parent.uid

    old = engine.queries[path]
    if !!old != !!ascending || (old == undefined && old != ascending)
      #d = engine.pairs.dirty
      unless old == undefined
        debugger
        engine.solved.remove(path)
        engine.queries.clean(path , continuation, operation.parent, scope)
      
      engine.queries[path] = ascending

      index = ascending ^ @inverted && 2 || 3
      engine.console.group '%s \t\t\t\t%o\t\t\t%c%s', (index == 2 && 'if' || 'else') + engine.Continuation.DESCEND, operation.parent[index], 'font-weight: normal; color: #999', continuation
      if branch = operation.parent[index]
        result = engine.Command(branch).solve(engine, branch, engine.Continuation(path, null,  engine.Continuation.DESCEND), scope)

      engine.console.groupEnd(path)

  # Capture commands generated by evaluation of arguments
  yield: (result, engine, operation, continuation, scope) ->
    # Condition result bubbled up, pick a branch
    if operation.parent.indexOf(operation) == -1
      if operation[0].key
        continuation = operation[0].key
        scope = engine.identity[operation[0].scope] || scope
      else
        continuation = engine.Continuation(continuation, null, engine.Continuation.DESCEND)
      if continuation?
        @update(engine.document || engine.abstract, operation.parent[1], continuation, scope, undefined, result)
      return true
      
Condition.define 'if', {}
Condition.define 'unless', {
  inverted: true
}
 
module.exports = Condition