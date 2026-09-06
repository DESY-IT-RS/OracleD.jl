# Build script for the OracleD.jl documentation with Documenter.jl.
#
# Usage:
#   julia --project=docs docs/make.jl
#
# (equivalently, from the `docs/` directory: `julia --project make.jl`).

using Documenter
using OracleD

makedocs(
    sitename = "OracleD.jl",
    authors  = "Dwayne Spiteri, Gordon Stewart and Konrad Kockler",
    format   = Documenter.HTML(
        # Uncomment once the package is hosted and set the canonical URL:
        # canonical = "https://<username>.github.io/<Repository>/stable/",
    ),
    # The package is still a local path development dependency (it is not yet
    # hosted on a public git remote), so disable the "edit this page" links
    # that Documenter would otherwise derive from a `git remote`.
    remotes = nothing,
    pages   = [
        "Home"       => "index.md",
        "Configuration" => "configuration.md",
        "Custom cluster makeup" => "custom-cluster.md",
        "Development" => "development.md",
        "API reference" => "api.md",
        "About"      => "about.md",
    ],
)

# Deployment to GitHub Pages via GitHub Actions (e.g. the standard
# julia-actions/julia-docdeploy workflow). Only runs on CI.
if get(ENV, "CI", "false") == "true"
    deploydocs(
        repo = "github.com/<username>/<Repository>.git", # TODO: set the repository
        devbranch = "main",
        push_preview = true,
    )
end
