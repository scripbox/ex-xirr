legacy_finance_func = fn d, v -> LegacyFinance.xirr(d, v) end

ex_xirr_func = fn d, v -> ExXirr.xirr(d, v) end

inputs = %{
  "date_values" => %{
    v: [
      1000,
      2000,
      -2000,
      -4000,
      1000,
      2000,
      -2000,
      -4000,
      1000,
      2000,
      -2000,
      2000
    ],
    d: [
      {2011, 12, 07},
      {2011, 12, 07},
      {2013, 05, 21},
      {2013, 05, 21},
      {2013, 06, 21},
      {2013, 07, 21},
      {2013, 07, 24},
      {2013, 08, 16},
      {2013, 09, 21},
      {2014, 01, 01},
      {2014, 02, 10},
      {2014, 03, 20}
    ]
  }
}

Benchee.run(
  %{
    "legacy finance" => fn %{d: dates, v: values} -> legacy_finance_func.(dates, values) end,
    "ex xirr" => fn %{d: dates, v: values} -> ex_xirr_func.(dates, values) end
  },
  formatters: [
    Benchee.Formatters.HTML,
    Benchee.Formatters.Console
  ],
  time: 15,
  warmup: 5,
  inputs: inputs
)
