### Domain: Solved values

Merges values from all other domains, 
enables anonymous constraints on immutable values

###

Domain  = require('../concepts/Domain')
Value = require('../commands/Value')

class Numeric extends Domain
  priority: 10

  # Numeric domains usually dont use worker
  url: null
  


Numeric.Value            = Command.extend.call Value
Numeric.Value.Solution   = Command.extend.call Value.Solution
Numeric.Value.Variable   = Command.extend.call Value.Variable, {group: 'linear'},
  get: (path, tracker, engine, scoped, engine, operation, continuation, scope) ->
    domain = engine.Variable.getDomain(operation, true, true)
    if !domain || domain.priority < 0
      domain = engine
    else if domain != engine
      if domain.structured
        clone = ['get', null, path, engine.Continuation(continuation || "")]
        if scope && scope != engine.scope
          clone.push(engine.identity.provide(scope))
        clone.parent = operation.parent
        clone.index = operation.index
        clone.domain = domain
        engine.update([clone])
        return
    if scoped
      scoped = engine.identity.solve(scoped)
    else
      scoped = scope
    return domain.watch(null, path, operation, engine.Continuation(continuation || contd || ""), scoped)
    
Numeric.Value.Expression = Command.extend.call Value.Expression {group: 'linear'},

  "+": (left, right) ->
    return left + right

  "-": (left, right) ->
    return left - right

  "*": (left, right) ->
    return left * right

  "/": (left, right) ->
    return left / right
    
    
module.exports = Numeric