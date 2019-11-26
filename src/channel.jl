_geti(x, i) = x
_geti(x::Container{T}, i) where T = x[i]

function channel(func::Function; ctype=Any, csize=0, remote=false, pid=myid())
  if remote
    return RemoteChannel(()->Channel(func;ctype=ctype, csize=csize), pid)
  else
    return Channel(func;ctype=ctype, csize=csize)
  end
end

function channels(n::Int, func::Function; ctype=Any, csize=0, remote=false, pid=myid())
  Tuple(channel(func;ctype=_geti(ctype, i), csize=_geti(csize, i), remote=_geti(remote, i), pid=_geti(pid, i)) for i = 1:n)
end

macro channel(_ex...)
  kws = Dict{Symbol, Any}(
    :ctype=>Any,
    :csize=>0,
    :remote=>false,
    :pid=>myid(),
  )
  for i = 1:length(_ex)-1
    mkw = _ex[i]
    if mkw isa Expr && mkw.head == :(=)
      if haskey(kws, mkw.args[1])
        if mkw.args[2] isa Number
          kws[mkw.args[1]] = mkw.args[2]
        else
          kws[mkw.args[1]] = :($(esc(mkw.args[2])))
        end
      else
        return Expr(:call, :error, "Invalid keyword argument: $(mkw.args[1])")
      end
    else
      return Expr(:call, :error, "channel expects only one non-keyword argument")
    end
  end

  set_channel_symbol!(x, s) = nothing
  set_channel_symbol!(ex::Expr, s) =
    for i = 1:length(ex.args)
      ms = ex.args[i]
      if ms isa Symbol && ms === :_
        ex.args[i] = s
        return
      else
        set_channel_symbol!(ex.args[i], s)
      end
    end

  ex = _ex[end]
  ex = (ex isa Expr && ex.head == :block) ? ex : Expr(:block, ex)
  ctype = kws[:ctype]
  csize = kws[:csize]
  remote = kws[:remote]
  pid = kws[:pid]

  c = gensym(:c)
  set_channel_symbol!(ex, c)

  body = Expr(:(->),
              Expr(:tuple, c),
              ex
              )

  chnc = Expr(:do,
              :(Channel(;ctype=$(ctype), csize=$(csize))),
              :($(esc(body)))
              )

  if remote isa Bool
    if remote
      return :(RemoteChannel(()->$chnc, $pid))
    else
      return chnc
    end
  else
    return :($remote ? RemoteChannel(()->$chnc, $pid) : $chnc)
  end
end


islist(ex) = false
islist(ex::Expr) = ex.head == :tuple || ex.head == :vect

macro channels(_ex...)
  kws = Dict{Symbol, Any}(
    :ctype=>:(Any),
    :csize=>0,
    :remote=>false,
    :pid=>myid(),
  )
  n = 0

  for i = 1:length(_ex)-1
    mkw = _ex[i]
    if mkw isa Expr && mkw.head == :(=)
      if haskey(kws, mkw.args[1])
        kws[mkw.args[1]] = mkw.args[2]
      elseif mkw.args[1] == :n
        n = mkw.args[2]
      else
        return Expr(:call, :error, "Invalid keyword argument: $(mkw.args[1])")
      end
    else
      return Expr(:call, :error, "channel expects only one non-keyword argument")
    end
  end

  ex = _ex[end]

  if n == 0
    return Expr(:call, :error, "missing keyword argument: n must be specified")
  end

  if n isa Number
    body = []
    d = [[] for i = 1:n]
    for (kw, vl) in kws
      @show kw, vl
      if islist(vl)
        if length(vl.args) != n
          return Expr(:call, :error, "keyword argument $kw length not matched: $(length(vl.args)) v.s. $n (expected)")
        else
          for i = 1:n
            x = vl.args[i]
            if x isa Number
              push!(d[i], :($kw = $x))
            elseif x isa Symbol
              push!(d[i], :($kw = _geti($(esc(x)), $i)))
            else
              sym = gensym(Symbol(kw, i))
              push!(body,
                    Expr(:local,
                         Expr(:(=),
                              sym,
                              :($(esc(x)))
                              )
                         )
                    )
              push!(d[i], Expr(:(=),
                               kw,
                               Expr(:call,
                                    :_geti,
                                    sym,
                                    i)
                               )
                    )
            end
          end
        end
      else
        if vl isa Number
          for i = 1:n
            push!(d[i], :($kw = $vl))
          end
        elseif vl isa Symbol
          for i = 1:n
            push!(d[i], :($kw = _geti($(esc(vl)), $i)))
          end
        else
          sym = gensym(kw)
          push!(body,
                Expr(:local,
                     Expr(:(=),
                          sym,
                          :($(esc(vl)))
                          )
                     )
                )
          for i = 1:n
            push!(d[i], Expr(:(=),
                             kw,
                             Expr(:call,
                                  :_geti,
                                  sym,
                                  i)
                             )
                  )
          end
        end
      end
    end

    chns = []
    for i = 1:n
      push!(chns,
            Expr(:macrocall,
                 Symbol("@channel"),
                 :(esc(__source__.line)),
                 d[i]...,
                 ex
                 )
            )
    end
    return Expr(:block, body..., Expr(:tuple, chns...))
  else
    set_channel_symbol!(x, s) = nothing
    set_channel_symbol!(ex::Expr, s) =
      for i = 1:length(ex.args)
        ms = ex.args[i]
        if ms isa Symbol && ms === :_
          ex.args[i] = s
          return
        else
          set_channel_symbol!(ex.args[i], s)
        end
      end

    c = gensym(:c)

    ex = (ex isa Expr && ex.head == :block) ? ex : Expr(:block, ex)
    set_channel_symbol!(ex, c)

    body = Expr(:(->),
                Expr(:tuple, c),
                ex
                )

    return quote
      local ctype = $(esc(kws[:ctype]))
      local csize = $(esc(kws[:csize]))
      local pid = $(esc(kws[:pid]))
      local remote = $(esc(kws[:remote]))
      local func = $(esc(body))
      channels($(esc(n)), func; ctype=ctype, csize=csize, pid=pid, remote=remote)
    end
  end
end
