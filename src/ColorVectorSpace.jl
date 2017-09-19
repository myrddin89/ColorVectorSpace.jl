__precompile__(true)

module ColorVectorSpace

using Colors, FixedPointNumbers, Compat
import StatsBase: histrange

import Base: ==, +, -, *, /, ^, <, ~
import Base: abs, abs2, clamp, convert, copy, div, eps, isfinite, isinf,
    isnan, isless, length, mapreduce, norm, oneunit, promote_array_type,
    promote_op, promote_rule, zero, trunc, floor, round, ceil, bswap,
    mod, rem, atan2, hypot, max, min, varm, real, typemin, typemax

export nan

# The unaryOps
import Base:      conj, sin, cos, tan, sinh, cosh, tanh,
                  asin, acos, atan, asinh, acosh, atanh,
                  sec, csc, cot, asec, acsc, acot,
                  sech, csch, coth, asech, acsch, acoth,
                  sinc, cosc, cosd, cotd, cscd, secd,
                  sind, tand, acosd, acotd, acscd, asecd,
                  asind, atand, rad2deg, deg2rad,
                  log, log2, log10, log1p, exponent, exp,
                  exp2, expm1, cbrt, sqrt, erf,
                  erfc, erfcx, erfi, dawson,
                  significand, lgamma,
                  gamma, lfact, frexp, modf, airy, airyai,
                  airyprime, airyaiprime, airybi, airybiprime,
                  besselj0, besselj1, bessely0, bessely1,
                  eta, zeta, digamma, float, middle

export dotc

@compat AbstractGray{T} = Color{T,1}
@compat TransparentRGB{C<:AbstractRGB,T}   = TransparentColor{C,T,4}
@compat TransparentGray{C<:AbstractGray,T} = TransparentColor{C,T,2}
@compat TransparentRGBFloat{C<:AbstractRGB,T<:AbstractFloat} = TransparentColor{C,T,4}
@compat TransparentGrayFloat{C<:AbstractGray,T<:AbstractFloat} = TransparentColor{C,T,2}
@compat TransparentRGBNormed{C<:AbstractRGB,T<:Normed} = TransparentColor{C,T,4}
@compat TransparentGrayNormed{C<:AbstractGray,T<:Normed} = TransparentColor{C,T,2}

@compat MathTypes{T,C} = Union{AbstractRGB{T},TransparentRGB{C,T},AbstractGray{T},TransparentGray{C,T}}

# convert(RGB{Float32}, NaN) doesn't and shouldn't work, so we need to reintroduce nan
nan{T<:AbstractFloat}(::Type{T}) = convert(T, NaN)
nan{C<:MathTypes}(::Type{C}) = _nan(eltype(C), C)
_nan{T<:AbstractFloat,C<:AbstractGray}(::Type{T}, ::Type{C}) = (x = convert(T, NaN); C(x))
_nan{T<:AbstractFloat,C<:TransparentGray}(::Type{T}, ::Type{C}) = (x = convert(T, NaN); C(x,x))
_nan{T<:AbstractFloat,C<:AbstractRGB}(::Type{T}, ::Type{C}) = (x = convert(T, NaN); C(x,x,x))
_nan{T<:AbstractFloat,C<:TransparentRGB}(::Type{T}, ::Type{C}) = (x = convert(T, NaN); C(x,x,x,x))

## Generic algorithms
mapreduce(f, op::Union{typeof(&), typeof(|)}, a::MathTypes) = f(a)  # ambiguity
mapreduce(f, op, a::MathTypes) = f(a)
Base.r_promote(::typeof(+), c::MathTypes) = mapc(x->Base.r_promote(+, x), c)

for f in (:trunc, :floor, :round, :ceil, :eps, :bswap)
    @eval $f{T}(g::Gray{T}) = Gray{T}($f(gray(g)))
    @eval Compat.@dep_vectorize_1arg Gray $f
end
eps{T}(::Type{Gray{T}}) = Gray(eps(T))
Compat.@dep_vectorize_1arg AbstractGray isfinite
Compat.@dep_vectorize_1arg AbstractGray isinf
Compat.@dep_vectorize_1arg AbstractGray isnan
Compat.@dep_vectorize_1arg AbstractGray abs
Compat.@dep_vectorize_1arg AbstractGray abs2
for f in (:trunc, :floor, :round, :ceil)
    @eval $f{T<:Integer}(::Type{T}, g::Gray) = Gray{T}($f(T, gray(g)))
end

for f in (:mod, :rem, :mod1)
    @eval $f(x::Gray, m::Gray) = Gray($f(gray(x), gray(m)))
end

# Real values are treated like grays
ColorTypes.gray(x::Real) = x

dotc{T<:Real}(x::T, y::T) = acc(x)*acc(y)
dotc(x::Real, y::Real) = dotc(promote(x, y)...)

# Return types for arithmetic operations
multype{A,B}(::Type{A}, ::Type{B}) = coltype(typeof(zero(A)*zero(B)))
sumtype{A,B}(::Type{A}, ::Type{B}) = coltype(typeof(zero(A)+zero(B)))
divtype{A,B}(::Type{A}, ::Type{B}) = coltype(typeof(zero(A)/oneunit(B)))
powtype{A,B}(::Type{A}, ::Type{B}) = coltype(typeof(zero(A)^zero(B)))
multype(a::Colorant, b::Colorant) = multype(eltype(a),eltype(b))
sumtype(a::Colorant, b::Colorant) = sumtype(eltype(a),eltype(b))
divtype(a::Colorant, b::Colorant) = divtype(eltype(a),eltype(b))
powtype(a::Colorant, b::Colorant) = powtype(eltype(a),eltype(b))

coltype{T<:Fractional}(::Type{T}) = T
coltype{T}(::Type{T})             = Float64

acctype{T<:FixedPoint}(::Type{T}) = FixedPointNumbers.floattype(T)
acctype{T<:Number}(::Type{T}) = T

acc(x::Number) = convert(acctype(typeof(x)), x)

# Scalar binary RGB operations require the same RGB type for each element,
# otherwise we don't know which to return
color_rettype{A<:AbstractRGB,B<:AbstractRGB}(::Type{A}, ::Type{B}) = _color_rettype(base_colorant_type(A), base_colorant_type(B))
color_rettype{A<:AbstractGray,B<:AbstractGray}(::Type{A}, ::Type{B}) = _color_rettype(base_colorant_type(A), base_colorant_type(B))
color_rettype{A<:TransparentRGB,B<:TransparentRGB}(::Type{A}, ::Type{B}) = _color_rettype(base_colorant_type(A), base_colorant_type(B))
color_rettype{A<:TransparentGray,B<:TransparentGray}(::Type{A}, ::Type{B}) = _color_rettype(base_colorant_type(A), base_colorant_type(B))
_color_rettype{A<:Colorant,B<:Colorant}(::Type{A}, ::Type{B}) = error("binary operation with $A and $B, return type is ambiguous")
_color_rettype{C<:Colorant}(::Type{C}, ::Type{C}) = C

color_rettype(c1::Colorant, c2::Colorant) = color_rettype(typeof(c1), typeof(c2))

arith_colorant_type(::C) where {C<:Colorant} = arith_colorant_type(C)
arith_colorant_type(::Type{C}) where {C<:Colorant} = base_colorant_type(C)
arith_colorant_type(::Type{Gray24}) = Gray
arith_colorant_type(::Type{AGray32}) = AGray
arith_colorant_type(::Type{RGB24}) = RGB
arith_colorant_type(::Type{ARGB32}) = ARGB

## Math on Colors. These implementations encourage inlining and,
## for the case of Normed types, nearly halve the number of multiplications (for RGB)

# Scalar RGB
copy(c::AbstractRGB) = c
(+)(c::AbstractRGB) = mapc(+, c)
(+)(c::TransparentRGB) = mapc(+, c)
(-)(c::AbstractRGB) = mapc(-, c)
(-)(c::TransparentRGB) = mapc(-, c)
(*)(f::Real, c::AbstractRGB) = arith_colorant_type(c){multype(typeof(f),eltype(c))}(f*red(c), f*green(c), f*blue(c))
(*)(f::Real, c::TransparentRGB) = arith_colorant_type(c){multype(typeof(f),eltype(c))}(f*red(c), f*green(c), f*blue(c), f*alpha(c))
function (*){T<:Normed}(f::Real, c::AbstractRGB{T})
    fs = f*(1/reinterpret(oneunit(T)))
    arith_colorant_type(c){multype(typeof(f),T)}(fs*reinterpret(red(c)), fs*reinterpret(green(c)), fs*reinterpret(blue(c)))
end
function (*){T<:Normed}(f::Normed, c::AbstractRGB{T})
    fs = reinterpret(f)*(1/widen(reinterpret(oneunit(T)))^2)
    arith_colorant_type(c){multype(typeof(f),T)}(fs*reinterpret(red(c)), fs*reinterpret(green(c)), fs*reinterpret(blue(c)))
end
function (/){T<:Normed}(c::AbstractRGB{T}, f::Real)
    fs = (one(f)/reinterpret(oneunit(T)))/f
    arith_colorant_type(c){divtype(typeof(f),T)}(fs*reinterpret(red(c)), fs*reinterpret(green(c)), fs*reinterpret(blue(c)))
end
function (/){T<:Normed}(c::AbstractRGB{T}, f::Integer)
    fs = (1/reinterpret(oneunit(T)))/f
    arith_colorant_type(c){divtype(typeof(f),T)}(fs*reinterpret(red(c)), fs*reinterpret(green(c)), fs*reinterpret(blue(c)))
end
(+){S,T}(a::AbstractRGB{S}, b::AbstractRGB{T}) = color_rettype(a, b){sumtype(S,T)}(red(a)+red(b), green(a)+green(b), blue(a)+blue(b))
(-){S,T}(a::AbstractRGB{S}, b::AbstractRGB{T}) = color_rettype(a, b){sumtype(S,T)}(red(a)-red(b), green(a)-green(b), blue(a)-blue(b))
(+)(a::TransparentRGB, b::TransparentRGB) =
    color_rettype(a, b){sumtype(a,b)}(red(a)+red(b), green(a)+green(b), blue(a)+blue(b), alpha(a)+alpha(b))
(-)(a::TransparentRGB, b::TransparentRGB) =
    color_rettype(a, b){sumtype(a,b)}(red(a)-red(b), green(a)-green(b), blue(a)-blue(b), alpha(a)-alpha(b))
(*)(c::AbstractRGB, f::Real) = (*)(f, c)
(*)(c::TransparentRGB, f::Real) = (*)(f, c)
(/)(c::AbstractRGB, f::Real) = (one(f)/f)*c
(/)(c::TransparentRGB, f::Real) = (one(f)/f)*c
(/)(c::AbstractRGB, f::Integer) = (one(eltype(c))/f)*c
(/)(c::TransparentRGB, f::Integer) = (one(eltype(c))/f)*c

isfinite{T<:Normed}(c::Colorant{T}) = true
isfinite(c::Colorant) = mapreducec(isfinite, &, true, c)
isnan{T<:Normed}(c::Colorant{T}) = false
isnan(c::Colorant) = mapreducec(isnan, |, false, c)
isinf{T<:Normed}(c::Colorant{T}) = false
isinf(c::Colorant) = mapreducec(isinf, |, false, c)
abs(c::AbstractRGB) = abs(red(c))+abs(green(c))+abs(blue(c)) # should this have a different name?
abs{T<:Normed}(c::AbstractRGB{T}) = Float32(red(c))+Float32(green(c))+Float32(blue(c)) # should this have a different name?
abs(c::TransparentRGB) = abs(red(c))+abs(green(c))+abs(blue(c))+abs(alpha(c)) # should this have a different name?
abs{T<:Normed}(c::TransparentRGB{T}) = Float32(red(c))+Float32(green(c))+Float32(blue(c))+Float32(alpha(c)) # should this have a different name?
abs2(c::AbstractRGB) = red(c)^2+green(c)^2+blue(c)^2
abs2{T<:Normed}(c::AbstractRGB{T}) = Float32(red(c))^2+Float32(green(c))^2+Float32(blue(c))^2
abs2(c::TransparentRGB) = (ret = abs2(color(c)); ret + convert(typeof(ret), alpha(c))^2)
norm(c::AbstractRGB) = sqrt(abs2(c))
norm(c::TransparentRGB) = sqrt(abs2(c))

oneunit{C<:AbstractRGB}(::Type{C})     = C(1,1,1)
oneunit{C<:TransparentRGB}(::Type{C})  = C(1,1,1,1)

zero{C<:AbstractRGB}(::Type{C})    = C(0,0,0)
zero{C<:TransparentRGB}(::Type{C}) = C(0,0,0,0)
zero{C<:YCbCr}(::Type{C}) = C(0,0,0)
zero{C<:HSV}(::Type{C}) = C(0,0,0)
oneunit(p::Colorant) = oneunit(typeof(p))
Base.one(c::Colorant) = Base.one(typeof(c))
zero(p::Colorant) = zero(typeof(p))

# These constants come from squaring the conversion to grayscale
# (rec601 luma), and normalizing
dotc{T<:AbstractRGB}(x::T, y::T) = 0.200f0 * acc(red(x))*acc(red(y)) + 0.771f0 * acc(green(x))*acc(green(y)) + 0.029f0 * acc(blue(x))*acc(blue(y))
dotc(x::AbstractRGB, y::AbstractRGB) = dotc(promote(x, y)...)

# Scalar Gray
copy(c::AbstractGray) = c
const unaryOps = (:~, :conj, :abs,
                  :sin, :cos, :tan, :sinh, :cosh, :tanh,
                  :asin, :acos, :atan, :asinh, :acosh, :atanh,
                  :sec, :csc, :cot, :asec, :acsc, :acot,
                  :sech, :csch, :coth, :asech, :acsch, :acoth,
                  :sinc, :cosc, :cosd, :cotd, :cscd, :secd,
                  :sind, :tand, :acosd, :acotd, :acscd, :asecd,
                  :asind, :atand, :rad2deg, :deg2rad,
                  :log, :log2, :log10, :log1p, :exponent, :exp,
                  :exp2, :expm1, :cbrt, :sqrt, :erf,
                  :erfc, :erfcx, :erfi, :dawson,
                  :significand, :lgamma,
                  :gamma, :lfact, :frexp, :modf, :airy, :airyai,
                  :airyprime, :airyaiprime, :airybi, :airybiprime,
                  :besselj0, :besselj1, :bessely0, :bessely1,
                  :eta, :zeta, :digamma)
for op in unaryOps
    @eval ($op)(c::AbstractGray) = $op(gray(c))
end

middle(c::AbstractGray) = arith_colorant_type(c)(middle(gray(c)))
middle(x::C, y::C) where {C<:AbstractGray} = arith_colorant_type(C)(middle(gray(x), gray(y)))

(*)(f::Real, c::AbstractGray) = arith_colorant_type(c){multype(typeof(f),eltype(c))}(f*gray(c))
(*)(f::Real, c::TransparentGray) = arith_colorant_type(c){multype(typeof(f),eltype(c))}(f*gray(c), f*alpha(c))
(*)(c::AbstractGray, f::Real) = (*)(f, c)
(*)(c::TransparentGray, f::Real) = (*)(f, c)
(/)(c::AbstractGray, f::Real) = (one(f)/f)*c
(/)(n::Number, c::AbstractGray) = n/gray(c)
(/)(c::TransparentGray, f::Real) = (one(f)/f)*c
(/)(c::AbstractGray, f::Integer) = (one(eltype(c))/f)*c
(/)(c::TransparentGray, f::Integer) = (one(eltype(c))/f)*c
(+){S,T}(a::AbstractGray{S}, b::AbstractGray{T}) = color_rettype(a,b){sumtype(S,T)}(gray(a)+gray(b))
(+)(a::TransparentGray, b::TransparentGray) = color_rettype(a,b){sumtype(eltype(a),eltype(b))}(gray(a)+gray(b),alpha(a)+alpha(b))
(-){S,T}(a::AbstractGray{S}, b::AbstractGray{T}) = color_rettype(a,b){sumtype(S,T)}(gray(a)-gray(b))
(-)(a::TransparentGray, b::TransparentGray) = color_rettype(a,b){sumtype(eltype(a),eltype(b))}(gray(a)-gray(b),alpha(a)-alpha(b))
(*){S,T}(a::AbstractGray{S}, b::AbstractGray{T}) = color_rettype(a,b){multype(S,T)}(gray(a)*gray(b))
(^){S}(a::AbstractGray{S}, b::Integer) = arith_colorant_type(a){powtype(S,Int)}(gray(a)^convert(Int,b))
(^){S}(a::AbstractGray{S}, b::Real) = arith_colorant_type(a){powtype(S,typeof(b))}(gray(a)^b)
(+)(c::AbstractGray) = c
(+)(c::TransparentGray) = c
(-)(c::AbstractGray) = typeof(c)(-gray(c))
(-)(c::TransparentGray) = typeof(c)(-gray(c),-alpha(c))
(/)(a::AbstractGray, b::AbstractGray) = gray(a)/gray(b)
div(a::AbstractGray, b::AbstractGray) = div(gray(a), gray(b))
(+)(a::AbstractGray, b::Number) = gray(a)+b
(-)(a::AbstractGray, b::Number) = gray(a)-b
(+)(a::Number, b::AbstractGray) = a+gray(b)
(-)(a::Number, b::AbstractGray) = a-gray(b)
max{T<:AbstractGray}(a::T, b::T) = T(max(gray(a),gray(b)))
max(a::AbstractGray, b::AbstractGray) = max(promote(a,b)...)
max(a::Number, b::AbstractGray) = max(promote(a,b)...)
max(a::AbstractGray, b::Number) = max(promote(a,b)...)
min{T<:AbstractGray}(a::T, b::T) = T(min(gray(a),gray(b)))
min(a::AbstractGray, b::AbstractGray) = min(promote(a,b)...)
min(a::Number, b::AbstractGray) = min(promote(a,b)...)
min(a::AbstractGray, b::Number) = min(promote(a,b)...)

norm(c::AbstractGray) = abs(gray(c))
abs(c::TransparentGray) = abs(gray(c))+abs(alpha(c)) # should this have a different name?
abs(c::TransparentGrayNormed) = Float32(gray(c)) + Float32(alpha(c)) # should this have a different name?
abs2(c::AbstractGray) = gray(c)^2
abs2{T<:Normed}(c::AbstractGray{T}) = Float32(gray(c))^2
abs2(c::TransparentGray) = gray(c)^2+alpha(c)^2
abs2(c::TransparentGrayNormed) = Float32(gray(c))^2 + Float32(alpha(c))^2
atan2(x::Gray, y::Gray) = atan2(convert(Real, x), convert(Real, y))
hypot(x::Gray, y::Gray) = hypot(convert(Real, x), convert(Real, y))
norm(c::TransparentGray) = sqrt(abs2(c))

(<)(g1::AbstractGray, g2::AbstractGray) = gray(g1) < gray(g2)
(<)(c::AbstractGray, r::Real) = gray(c) < r
(<)(r::Real, c::AbstractGray) = r < gray(c)
isless(g1::AbstractGray, g2::AbstractGray) = isless(gray(g1), gray(g2))
isless(c::AbstractGray, r::Real) = isless(gray(c), r)
isless(r::Real, c::AbstractGray) = isless(r, gray(c))
Base.isapprox(x::AbstractGray, y::AbstractGray; kwargs...) = isapprox(gray(x), gray(y); kwargs...)
Base.isapprox(x::TransparentGray, y::TransparentGray; kwargs...) = isapprox(gray(x), gray(y); kwargs...) && isapprox(alpha(x), alpha(y); kwargs...)
Base.isapprox(x::AbstractRGB, y::AbstractRGB; kwargs...) = isapprox(red(x), red(y); kwargs...) && isapprox(green(x), green(y); kwargs...) && isapprox(blue(x), blue(y); kwargs...)
Base.isapprox(x::TransparentRGB, y::TransparentRGB; kwargs...) = isapprox(alpha(x), alpha(y); kwargs...) && isapprox(red(x), red(y); kwargs...) && isapprox(green(x), green(y); kwargs...) && isapprox(blue(x), blue(y); kwargs...)

function Base.isapprox{Cx<:MathTypes,Cy<:MathTypes}(x::AbstractArray{Cx},
                                                    y::AbstractArray{Cy};
                                                    rtol::Real=Base.rtoldefault(eltype(Cx),eltype(Cy)),
                                                    atol::Real=0,
                                                    norm::Function=vecnorm)
    d = norm(x - y)
    if isfinite(d)
        return d <= atol + rtol*max(norm(x), norm(y))
    else
        # Fall back to a component-wise approximate comparison
        return all(ab -> isapprox(ab[1], ab[2]; rtol=rtol, atol=atol), zip(x, y))
    end
end

zero{C<:TransparentGray}(::Type{C}) = C(0,0)
oneunit{C<:TransparentGray}(::Type{C}) = C(1,1)

dotc{T<:AbstractGray}(x::T, y::T) = acc(gray(x))*acc(gray(y))
dotc(x::AbstractGray, y::AbstractGray) = dotc(promote(x, y)...)

float{T<:Gray}(::Type{T}) = typeof(float(zero(T)))

# Mixed types
(+)(a::MathTypes, b::MathTypes) = (+)(Base.promote_noncircular(a, b)...)
(-)(a::MathTypes, b::MathTypes) = (-)(Base.promote_noncircular(a, b)...)

Compat.@dep_vectorize_2arg Gray max
Compat.@dep_vectorize_2arg Gray min

# Arrays
+{C<:MathTypes}(A::AbstractArray{C}) = A

(+){CV<:AbstractRGB}(A::AbstractArray{CV}, b::AbstractRGB) = (.+)(A, b)
(+){CV<:AbstractRGB}(b::AbstractRGB, A::AbstractArray{CV}) = (.+)(b, A)
(-){CV<:AbstractRGB}(A::AbstractArray{CV}, b::AbstractRGB) = (.-)(A, b)
(-){CV<:AbstractRGB}(b::AbstractRGB, A::AbstractArray{CV}) = (.-)(b, A)
(*){T<:Number}(A::AbstractArray{T}, b::AbstractRGB) = A.*b
(*){T<:Number}(b::AbstractRGB, A::AbstractArray{T}) = A.*b

(+){CV<:TransparentRGB}(A::AbstractArray{CV}, b::TransparentRGB) = (.+)(A, b)
(+){CV<:TransparentRGB}(b::TransparentRGB, A::AbstractArray{CV}) = (.+)(b, A)
(-){CV<:TransparentRGB}(A::AbstractArray{CV}, b::TransparentRGB) = (.-)(A, b)
(-){CV<:TransparentRGB}(b::TransparentRGB, A::AbstractArray{CV}) = (.-)(b, A)
(*){T<:Number}(A::AbstractArray{T}, b::TransparentRGB) = A.*b
(*){T<:Number}(b::TransparentRGB, A::AbstractArray{T}) = A.*b

(+){CV<:AbstractGray}(A::AbstractArray{CV}, b::AbstractGray) = (.+)(A, b)
(+){CV<:AbstractGray}(b::AbstractGray, A::AbstractArray{CV}) = (.+)(b, A)
(-){CV<:AbstractGray}(A::AbstractArray{CV}, b::AbstractGray) = (.-)(A, b)
(-){CV<:AbstractGray}(b::AbstractGray, A::AbstractArray{CV}) = (.-)(b, A)
(*){T<:Number}(A::AbstractArray{T}, b::AbstractGray) = A.*b
(*){T<:Number}(b::AbstractGray, A::AbstractArray{T}) = A.*b
(/){C<:AbstractGray}(A::AbstractArray{C}, b::AbstractGray) = A./b

(+){CV<:TransparentGray}(A::AbstractArray{CV}, b::TransparentGray) = (.+)(A, b)
(+){CV<:TransparentGray}(b::TransparentGray, A::AbstractArray{CV}) = (.+)(b, A)
(-){CV<:TransparentGray}(A::AbstractArray{CV}, b::TransparentGray) = (.-)(A, b)
(-){CV<:TransparentGray}(b::TransparentGray, A::AbstractArray{CV}) = (.-)(b, A)
(*){T<:Number}(A::AbstractArray{T}, b::TransparentGray) = A.*b
(*){T<:Number}(b::TransparentGray, A::AbstractArray{T}) = A.*b

varm{C<:AbstractGray}(v::AbstractArray{C}, s::AbstractGray; corrected::Bool=true) =
        varm(map(gray,v),gray(s); corrected=corrected)
real{C<:AbstractGray}(::Type{C}) = real(eltype(C))

#histrange for Gray type
histrange{T}(v::AbstractArray{Gray{T}}, n::Integer) = histrange(convert(Array{Float32}, map(gray, v)), n, :right)

# To help type inference
promote_array_type{T<:Real,C<:MathTypes}(F, ::Type{T}, ::Type{C}) = base_colorant_type(C){Base.promote_array_type(F, T, eltype(C))}
promote_rule{T<:Real,C<:AbstractGray}(::Type{T}, ::Type{C}) = promote_type(T, eltype(C))

typemin{T<:ColorTypes.AbstractGray}(::Type{T}) = T(typemin(eltype(T)))
typemax{T<:ColorTypes.AbstractGray}(::Type{T}) = T(typemax(eltype(T)))

typemin{T<:ColorTypes.AbstractGray}(::T) = T(typemin(eltype(T)))
typemax{T<:ColorTypes.AbstractGray}(::T) = T(typemax(eltype(T)))

# deprecations
function Base.one(::Type{C}) where {C<:Union{TransparentGray,AbstractRGB,TransparentRGB}}
    Base.depwarn("one($C) will soon switch to returning 1; you might need to switch to `oneunit`", :one)
    C(_onetuple(C)...)
end
_onetuple(::Type{C}) where {C<:Colorant{T,N}} where {T,N} = ntuple(d->1, Val(N))

for f in (:min, :max)
    @eval begin
        @deprecate($f{T<:Gray}(x::Number, y::AbstractArray{T}), $f.(x, y))
        @deprecate($f{T<:Gray}(x::AbstractArray{T}, y::Number), $f.(x, y))
    end
end

end
