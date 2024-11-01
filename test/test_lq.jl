using Test
using LegendSpecFits
using Unitful
using Distributions
using Plots


# Define the test function
@testset "LQ_cut Test" begin
    # Define energy peak parameters
    DEP_µ = 1000.0u"keV"
    DEP_σ = 1.0u"keV"
    n_peak = 5000  # Peak events
    n_bg = n_peak ÷ 10  # Background events

    # Energy calibration (fixed at DEP_µ for all events)
    e_cal = vcat(fill(DEP_µ, n_peak + n_bg), fill(DEP_µ - 5* DEP_σ, n_bg ÷ 2), fill(DEP_µ + 5* DEP_σ, n_bg ÷ 2) )  # Fixed energy value for peak and background

    # LQ Classifier
    # Peak 1: Normally distributed LQ values
    lq_classifier_peak1 = randn(n_peak)
    # Peak 2: Flat background within the peak
    lq_classifier_peak2 = -4 .+ 14 .* rand(n_bg)

    # Below: Flat background below the peak
    lq_classifier_below = -4 .+ 14 .* rand(n_bg ÷ 2)
    lq_classifier_above = -4 .+ 14 .* rand(n_bg ÷ 2)

    # Combine all cases into the LQ classifier array
    lq_classifier_combined = vcat(lq_classifier_peak1, lq_classifier_peak2, lq_classifier_below, lq_classifier_above)

    # Call the LQ_cut function
    result, report = LQ_cut(DEP_µ, DEP_σ, e_cal, lq_classifier_combined)

    plot(report.temp_hists.hist_DEP, label="LQ SEP")
    plot!(report.temp_hists.hist_sb1, label="LQ SB1")
    plot!(report.temp_hists.hist_sb2, label="LQ SB2")
    plot!(report.temp_hists.hist_subtracted, label="DEP Subtracted")
    plot(report.temp_hists.hist_corrected, label="original histogram")
    plot!(report.fit_report.f_fit, label="Fit function")

    # Extract the cutoff value
    report.fit_result.μ
    report.fit_result.σ
    cut_3σ = result.cut
  
    # Calculate the expected mean, sigma and cutoff value
    expected_mean = mean(lq_classifier_peak1)
    expected_sigma = std(lq_classifier_peak1)
    expected_cut = expected_mean + 3 * expected_sigma

    # Test the parameters
    @test isapprox(report.fit_result.μ, expected_mean, atol=0.05)
    @test isapprox(report.fit_result.σ, expected_sigma, atol=0.05)
    @test isapprox(cut_3σ, expected_cut, atol=0.1)
end
