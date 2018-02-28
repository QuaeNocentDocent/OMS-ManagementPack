
$items=@()
foreach($row in $result.Values.tables[0].rows) {
    $column=0
    $item=@{}
    foreach($key in $result.Values.tables[0].columns) {
        $item.Add($key.Name,$row[$column] -as $key.Type)
        $column++        
    }
    $items+=$item
}