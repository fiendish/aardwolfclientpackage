function GagBlankLine(index, sequence)
    -- Gags the next line if it's blank. The index and sequence variables give extra control over operation but should
    -- only be useful if running many of these simultaneously from the same plugin.
    index = index or 1
    sequence = sequence or 1

    AddTriggerEx(
        "blank_line_gag_trigger"..index,
        "^$",
        "DeleteTrigger('blank_line_gag_trigger_unset"..index.."');StopEvaluatingTriggers(true)",
        trigger_flag.Enabled + trigger_flag.RegularExpression + trigger_flag.Temporary + trigger_flag.OneShot + trigger_flag.OmitFromLog + trigger_flag.OmitFromOutput,
        custom_colour.NoChange,
        0,
        "",
        "",
        sendto.script,
        sequence
    )
    AddTriggerEx(
        "blank_line_gag_trigger_unset"..index,
        ".+",
        "DeleteTrigger('blank_line_gag_trigger"..index.."')",
        trigger_flag.Enabled + trigger_flag.RegularExpression + trigger_flag.Temporary + trigger_flag.OneShot + trigger_flag.KeepEvaluating,
        custom_colour.NoChange,
        0,
        "",
        "",
        sendto.script,
        0
    )
end


function UngagBlankLine(index)
    DeleteTrigger("blank_line_gag_trigger"..index)
    DeleteTrigger("blank_line_gag_trigger_unset"..index)
end