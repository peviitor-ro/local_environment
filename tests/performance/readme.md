# Performance Testing

This directory stores curated performance evidence.

## Workflow
- Use the JMeter plans in `environments/*/*.jmx` to simulate production traffic.
- Export the final report as PDF and add it here with a descriptive filename (e.g., `Performance.Report_XXVusers_YYYYMMDD.pdf`).
- Document notable findings in a companion Markdown file if the report requires context.

## Cleanup
Remove transient files (`results.jtl`, raw logs) before committing. Only keep finalized artifacts that help reviewers understand the system's load behaviour.
