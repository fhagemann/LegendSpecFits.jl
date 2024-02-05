# This file is a part of LegendSpecFits.jl, licensed under the MIT License (MIT).

"""
    LegendSpecFits

Template for Julia packages.
"""
module LegendSpecFits

using LinearAlgebra
using Statistics
using Random

using ArgCheck
using ArraysOfArrays
using BAT
using Distributions
using FillArrays
using ForwardDiff
using Interpolations
using IntervalSets
using InverseFunctions
using IrrationalConstants
using LegendDataManagement
using LegendDataTypes: fast_flatten
using LinearRegression
using LsqFit
using Optim
using PropDicts
using RadiationSpectra
using Roots
using SpecialFunctions
using StatsBase
using StructArrays
using Tables
using TypedTables
using Unitful
using ValueShapes

include("utils.jl")
include("peakshapes.jl")
include("likelihoods.jl")
include("priors.jl")
include("cut.jl")
include("aoefit.jl")
include("filter_optimization.jl")
include("singlefit.jl")
include("specfit.jl")
include("fwhm.jl")
include("simple_calibration.jl")
include("auto_calibration.jl")
include("aoe_calibration.jl")
include("specfit_combined.jl")
include("specfit_testdata.jl")
include("ctc.jl")
include("qc.jl")
include("gof.jl")
include("precompile.jl")

end # module
