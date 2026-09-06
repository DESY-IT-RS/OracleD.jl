# About

## Project status

OracleD.jl is the Julia implementation of the **ORACLE-D** framework,
developed in parallel with the original Python version. The package version
is declared in `Project.toml` (1.1.0); release versioning follows the parent
ORACLE-D releases.

## Copyright and license

Copyright 2023-2026 Deutsches Elektronen Synchrotron DESY and the
University of Glasgow.

Original authors: Dwayne Spiteri and Gordon Stewart.

All code in the `src/` directory and subsequent subdirectory structure is
licensed under the Apache License, Version 2.0 (the "License"); you may not
use this file except in compliance with the License. You may obtain a copy
of the License at

```
http://www.apache.org/licenses/LICENSE-2.0
```

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS, WITHOUT
WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. See the
License for the specific language governing permissions and limitations
under the License.

See the `LICENSE` and `NOTICE` files in the repository root for details.

## Contributors

Dwayne Spiteri, Gordon Stewart and Konrad Kockler.

## Acknowledgements

The measurements used here to categorise the different types of server come
from running the [HEPScore23 benchmark](https://w3.hepix.org/benchmarking/how_to_run_HS23.html)
on compute nodes. For the server examples used in ORACLE-D these were taken
by **Emanuele Simili** at the University of Glasgow in February 2024 and
**Jan Hartmann** at DESY in May 2025.

The carbon intensity data for the UK is taken from the [UK National Grid
ESO](https://www.nationalgrideso.com/data-portal/national-carbon-intensity-forecast/national_carbon_intensity_forecast),
interpolated to fill gaps in the data, and for Germany from
[Agorameter](https://www.agora-energiewende.de/daten-tools/agorameter) and
[Green Grid Compass](https://www.greengrid-compass.eu/).

This code was partially written for the RF2.0 project, which has received
funding from the European Union's Horizon Europe research and innovation
programme under grant agreement No. 101131850 and from the Swiss State
Secretariat for Education Research and Innovation (SERI).
