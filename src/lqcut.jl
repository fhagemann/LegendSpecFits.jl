"""
    lq_norm::Vector{Float64}, tdrift::Vector{<:Unitful.RealOrRealQuantity}, e_cal::Array{<:Unitful.Energy{<:Real}}, DEP_µ::Unitful.AbstractQuantity, DEP_σ::Unitful.AbstractQuantity;
    DEP_edgesigma::Float64 = 3.0 , mode::Symbol = :gaussian, lower_exclusion::Float64 = 0.005, upper_exclusion::Float64 = 0.98, drift_cutoff_sigma::Float64 = 2.0, e_expression::Union{String,Symbol}="e")

Perform the drift time correction on the LQ data using the DEP peak. The function cuts outliers in lq and drift time, then performs a linear fit on the remaining data. The data is Corrected by subtracting the linear fit from the lq data.
# Returns
    * `result`: NamedTuple of the corrected lq data, the box used for the linear fit and the drift time function
    * `report`: NamedTuple of the histograms used for the fit
"""
function lq_drift_time_correction(
    lq_norm::Vector{Float64}, tdrift::Vector{<:Unitful.RealOrRealQuantity}, e_cal::Vector{<:Unitful.Energy{<:Real}}, DEP_µ::Unitful.AbstractQuantity, DEP_σ::Unitful.AbstractQuantity;
     DEP_edgesigma::Float64 = 3.0 , mode::Symbol = :gaussian, lower_exclusion::Float64 = 0.005, upper_exclusion::Float64 = 0.98, drift_cutoff_sigma::Float64 = 2.0,
     prehist_sigma::Float64 = 3.0, e_expression::Union{String,Symbol}="e")

    #calculate DEP edges
    DEP_left = DEP_µ - DEP_edgesigma * DEP_σ
    DEP_right = DEP_µ + DEP_edgesigma * DEP_σ

    #cut data to DEP peak
    lq_DEP = lq_norm[DEP_left .< e_cal .< DEP_right]
    t_tcal = ustrip.(tdrift[DEP_left .< e_cal .< DEP_right])

    #lq cutoff
    low_cut_value = quantile(lq_DEP, lower_exclusion)  # 0.5% quantile
    high_cut_value = quantile(lq_DEP, upper_exclusion)  # 2% quantile

    ideal_bin_width = get_friedman_diaconis_bin_width(lq_DEP[low_cut_value .< lq_DEP .< high_cut_value])

    lq_prehist = fit(Histogram, lq_DEP, range(low_cut_value, high_cut_value, step=ideal_bin_width))
    lq_prestats = estimate_single_peak_stats(lq_prehist)

    lq_start = lq_prestats.peak_pos - prehist_sigma * lq_prestats.peak_sigma
    lq_stop = lq_prestats.peak_pos + prehist_sigma * lq_prestats.peak_sigma

    lq_result, lq_report = fit_binned_trunc_gauss(lq_prehist, (low=lq_start, high=lq_stop, max=NaN))
    µ_lq = mvalue(lq_result.μ)
    σ_lq = mvalue(lq_result.σ)

    #set cutoff in lq dimension for later fit
    lq_lower = µ_lq - drift_cutoff_sigma * σ_lq 
    lq_upper = µ_lq + drift_cutoff_sigma * σ_lq 


    #t_tcal cutoff; method dependant on detector type
    if mode == :gaussian 
        
        #ideal bin width for histogram
        ideal_bin_width = get_friedman_diaconis_bin_width(t_tcal)

        drift_prehist = fit(Histogram, t_tcal, range(minimum(t_tcal), stop=maximum(t_tcal), step=ideal_bin_width))
        drift_prestats = estimate_single_peak_stats(drift_prehist)
        drift_start = drift_prestats.peak_pos - prehist_sigma * drift_prestats.peak_sigma
        drift_stop = drift_prestats.peak_pos + prehist_sigma * drift_prestats.peak_sigma
        
        drift_edges = range(drift_start, stop=drift_stop, length=ideal_length)
        drift_hist_DEP = fit(Histogram, t_tcal, drift_edges)
        
        drift_result, drift_report = fit_binned_trunc_gauss(drift_hist_DEP)
        µ_t = mvalue(drift_result.μ)
        σ_t = mvalue(drift_result.σ)

        #set cutoff in drift time dimension for later fit
        t_lower = µ_t - drift_cutoff_sigma * σ_t
        t_upper = µ_t + drift_cutoff_sigma * σ_t
    elseif mode == :percentile
        #set cutoff at the 15% and 95% percentile
        t_lower = quantile(t_tcal, 0.15)
        t_upper = quantile(t_tcal, 0.95)
        drift_prehist = nothing
        drift_report = nothing

    elseif mode == :double_gaussian
        #create histogram for drift time
        drift_prehist = fit(Histogram, t_tcal, range(minimum(t_tcal), stop=maximum(t_tcal), length=100))
        drift_prestats = estimate_single_peak_stats(drift_prehist)

        #fit histogram with double gaussian
        drift_result, drift_report = fit_binned_double_gauss(drift_prehist, drift_prestats)
        
        #set cutoff at the x-value where the fit function is 10% of its maximum value
        x_values = -1000:0.5:5000  
        max_value = maximum(drift_report.f_fit.(x_values))
        threshold = 0.1 * max_value

        g(x) = drift_report.f_fit(x) - threshold
        x_at_threshold = find_zeros(g, minimum(x_values), maximum(x_values))

        t_lower = minimum(x_at_threshold)
        t_upper = maximum(x_at_threshold)
    else
        error("Mode $mode not supported")
    end

    #store cutoff values in box to return later    
    box = (lq_lower = lq_lower, lq_upper = lq_upper, t_lower = t_lower, t_upper = t_upper)

    #cut data according to cutoff values
    lq_cut = lq_DEP[lq_lower .< lq_DEP .< lq_upper .&& t_lower .< t_tcal .< t_upper]
    t_cut = t_tcal[lq_lower .< lq_DEP .< lq_upper .&& t_lower .< t_tcal .< t_upper]

    #linear fit
    result_µ, report_µ = chi2fit(1, t_cut, lq_cut; uncertainty=true)
    parameters = mvalue(result_µ.par)
    drift_time_func(x) = parameters[1] .+ parameters[2] .* x

    #property function for drift time correction
    lq_class_func = "lq / $e_expression - ($(parameters[2]) * (qdrift / $e_expression) + $(parameters[1]))"
    lq_class_func_generic = "lq / e  - (slope * qdrift / e + y_inter)"

    #create result and report
    result = (
    func = lq_class_func,
    func_generic = lq_class_func_generic,
    )

    report = (
    lq_prehist = lq_prehist, 
    lq_report = lq_report, 
    drift_prehist = drift_prehist, 
    drift_report = drift_report,
    lq_box = box,
    drift_time_func = drift_time_func,
    DEP_left = DEP_left,
    DEP_right = DEP_right,
    )
    

    return result, report
end
export lq_drift_time_correction

"""
    DEP_µ::Unitful.Energy, DEP_σ::Unitful.Energy, e_cal::Vector{<:Unitful.Energy}, lq_classifier::Vector{Float64}; lower_exclusion::Float64=0.005, upper_exclusion::Float64=0.95, cut_sigma::Float64=3.0)

Evaluates the cutoff value for the LQ cut. The function performs a binned gaussian fit on the sidebandsubtracted LQ histogram and evaluates the cutoff value difined at 3σ of the fit.
# Returns
    * `result`: NamedTuple of the cutoff value and the fit result
    * `report`: NamedTuple of the histograms used for the fit
"""
function LQ_cut(
    DEP_µ::Unitful.Energy, DEP_σ::Unitful.Energy, e_cal::Vector{<:Unitful.Energy}, lq_classifier::Vector{Float64}; lower_exclusion::Float64=0.005, upper_exclusion::Float64=0.95, cut_sigma::Float64=3.0)

    # Define sidebands
    lq_DEP = lq_classifier[DEP_µ - 4.5 * DEP_σ .< e_cal .< DEP_µ + 4.5 * DEP_σ]
    lq_sb1 = lq_classifier[DEP_µ -  2 * 4.5 * DEP_σ .< e_cal .< DEP_µ - 4.5 * DEP_σ]
    lq_sb2 = lq_classifier[DEP_µ + 4.5 * DEP_σ .< e_cal .< DEP_µ + 2 * 4.5 * DEP_σ]
    
    # Generate values for histogram edges
    #exclude outliers
    low_cut_value = quantile(lq_DEP, lower_exclusion)  # 0.5% quantile
    high_cut_value = quantile(lq_DEP, upper_exclusion)  # 95% quantile
    prehist = fit(Histogram, lq_DEP, range(low_cut_value, high_cut_value, length=100))
    prestats = estimate_single_peak_stats(prehist)
    start = prestats.peak_pos - 3*prestats.peak_sigma
    stop = prestats.peak_pos + 3*prestats.peak_sigma
    edges = range(start, stop=stop, length=71) 

    # Create histograms with the same bin edges
    hist_DEP = fit(Histogram, lq_DEP, edges)
    hist_sb1 = fit(Histogram, lq_sb1, edges)
    hist_sb2 = fit(Histogram, lq_sb2, edges)
    
    # Subtract histograms
    weights_subtracted = hist_DEP.weights .- hist_sb1.weights .- hist_sb2.weights
    hist_subtracted = Histogram(edges, weights_subtracted)

    # Replace negative bins with 0
    weights_corrected = max.(weights_subtracted, 0)
    hist_corrected = Histogram(edges, weights_corrected)
    
    # Create a named tuple of temporary histograms for crosschecks
    temp_hists = (prehist = prehist, hist_DEP = hist_DEP, hist_sb1 = hist_sb1, hist_sb2 = hist_sb2, hist_subtracted = hist_subtracted, hist_corrected = hist_corrected)

    # Fit the sideband subtracted histogram
    fit_result, fit_report = fit_binned_trunc_gauss(hist_corrected)

    #final cutoff value defined by "cut_sigma"
    cut_3σ = fit_result.μ + cut_sigma * fit_result.σ

    result = (
        cut = cut_3σ,

    )

    report = (
        fit_result = fit_result,
        temp_hists = temp_hists,
        fit_report = fit_report,
    )

    return result, report
end
export LQ_cut
