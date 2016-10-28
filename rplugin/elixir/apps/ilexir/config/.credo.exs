%{
  configs: [
    %{
      name: "default",
      files: %{
        included: ["lib/", "hosted/"],
        excluded: []
      },
      checks: [
        {Credo.Check.Design.AliasUsage, priority: :low},
        {Credo.Check.Readability.MaxLineLength, priority: :low, max_length: 120},
        {Credo.Check.Consistency.LineEndings, false},
        {Credo.Check.Design.TagFIXME, true},
      ]
    }
  ]
}
