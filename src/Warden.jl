module Warden

const JULIA_DIR = normpath(Sys.BINDIR, "..", "share", "julia")
include(normpath(JULIA_DIR, "Compiler", "test", "EAUtils.jl"))
using .EAUtils

using .Base: @propagate_inbounds

export no_escape, code_escapes, @code_escapes

struct WardedArray{T, N, AnalysisHandle} <: DenseArray{T, N}
    ptr::Ptr{T}
    size::NTuple{N, Int}
    handle::AnalysisHandle
end
const WardedVector{T, AnalysisHandle} = WardedArray{T, 1, AnalysisHandle}
Base.size(v::WardedArray) = v.size
@propagate_inbounds function Base.getindex(v::WardedArray, i::Integer)
    @boundscheck (i ∈ 1:length(v)) || bnds_err(length(v), i)
    GC.@preserve v begin
        unsafe_load(v.ptr, i)
    end
end
@propagate_inbounds function Base.setindex!(v::WardedArray{T}, x, i::Integer) where {T}
    @boundscheck (i ∈ 1:length(v)) || bnds_err(length(v), i)
    GC.@preserve v begin
        unsafe_store!(v.ptr, convert(T, x), i)
    end
end

@propagate_inbounds function Base.getindex(A::WardedArray, inds::Integer...)
    i = LinearIndices(A)[inds...]
    A[i]
end
@propagate_inbounds function Base.setindex!(A::WardedArray{T}, x, inds::Integer...) where {T}
    i = LinearIndices(A)[inds...]
    setindex!(A, x, i)
end


@noinline bnds_err(len, i) =
    error("Attempted out of bounds length $len WardedArray access at index $i")


Base.iscontiguous(::WardedArray) = true
Base.iscontiguous(::Type{<:WardedArray}) = true

const ALLOCA_LIMIT = 10_000

deval(::Val{x}) where {x} = x

function no_escape(f, ::Type{T}, ::Val{SZ}) where {T, SZ}
    isbitstype(T) || error("Only isbits is allowed!")
    if SZ isa Integer
        len = SZ
        sz = (len,)
    elseif SZ isa Tuple{Vararg{Integer}}
        len = prod(SZ)
        sz = SZ
    else
        error("Invalid size ", SZ, " expected an integer or tuple of integers.")
    end
    let v_dummy = WardedArray(Ptr{T}(0), sz, Ref(nothing))
        check_escapes(f, v_dummy)
    end
    nbytes = len * sizeof(T)
    if nbytes <= ALLOCA_LIMIT
        _with_alloca(f, T, sz, Val(len))
    else
        _with_malloc(f, T, sz, nbytes)
    end
end
function no_escape(f, ::Type{T}, sz...) where {T}
    isbitstype(T) || error("Only isbits is allowed!")
    let v_dummy = WardedArray(Ptr{T}(0), sz, Ref(nothing))
        check_escapes(f, v_dummy)
    end
    nbytes = sizeof(T) * prod(sz)
    _with_malloc(f, T, sz, nbytes)
end

function _with_alloca(f, ::Type{T}, n, ::Val{AllocSize}) where {T, AllocSize}
    mem = Ref{NTuple{AllocSize, T}}()
    GC.@preserve mem begin
        ptr::Ptr{T} = pointer_from_objref(mem)
        v = WardedArray(ptr, n, nothing)
        f(v)
    end
end
function _with_malloc(f, ::Type{T}, sz, nbytes) where {T}
    ptr::Ptr{T} = Libc.malloc(nbytes)
    v = WardedArray(ptr, sz, nothing)
    try
        f(v)
    finally
        Libc.free(ptr)
    end
end

# using Accessors
# function check_escapes(f, ::Type{T}, n, handle) where {T}
#     _check_escapes(handle) do handle
#         v = WardedArray(Ptr{T}(0), n, handle)
#         f(v)
#     end
# end
check_escapes(f, v) = _check_escapes(f, v)
function __check_escapes(world::UInt, mthd, this, fargtypes)
    tt = Base.to_tuple_type(fargtypes)
    match = Base._which(tt; raise=false, world)
    match === nothing && return nothing 
    mi = Core.Compiler.specialize_method(match)
    result = code_escapes(mi; world)

    return_escape = result.state[Core.Argument(2)].ReturnEscape
    throw_escape = !isempty(result.state[Core.Argument(2)].ThrownEscape)
    if return_escape || throw_escape
        throw(EscapeError(result))
    end
    body = nothing
    file = :none
    lam = Expr(:lambda, Any[:f, :v],
               Expr(:var"scope-block",
                    Expr(:block,
                         LineNumberNode(Int(mthd.line), mthd.file),
                         Expr(:meta, :push_loc, file, :var"@generated body"),
                         Expr(:return, body),
                         Expr(:meta, :pop_loc))))
    return Base.generated_body_to_codeinfo(lam, @__MODULE__(), true)
end

function refresh()
    @eval function _check_escapes(args...)
        $(Expr(:meta, :generated_only))
        $(Expr(:meta, :generated, __check_escapes))
    end
end
refresh()

struct EscapeError
    result
end
function Base.showerror(io::IO, (;result)::EscapeError)
    println(io, "EscapeError: You've let an argument you used in `no_escape` escape the function body. Here is the compiler escape analysis result:")
    print(io, result)
end

end # module Jailer
