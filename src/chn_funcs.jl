function merges!(cs::Container{<:ChannelLike}, dest=myid(); csize=0, ctype=Any)
  return @channel csize=csize ctype=ctype remote=dest!=myid() pid=dest begin
    while true
      v = @try_call! map(cs) do c
        take!(c)
      end break
      put!(_, v)
    end
  end
end

function batches!(c::ChannelLike{T}, n=1; csize=0, ctype=Any) where T
  res = T[]
  sizehint!(res, n)
  for i = 1:n
    v = @try_take! c if isempty(res)
      rethrow()
    else
      break
    end
    push!(res, v)
  end
  res
end
