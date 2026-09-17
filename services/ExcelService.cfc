component output=false {
    function init(){return this;}

    array function readSheet(required string path, required string sheetName, numeric headerRow=1){
        var fis=createObject("java","java.io.FileInputStream").init(arguments.path);
        var wb="";
        try{wb=createObject("java","org.apache.poi.ss.usermodel.WorkbookFactory").create(fis);}catch(any e){fis.close();throw(type="Logicore.Excel",message="The uploaded file is not a readable Excel workbook (#getFileFromPath(arguments.path)#).",detail=e.message);}
        try{
            var sheet=wb.getSheet(arguments.sheetName);
            if(isNull(sheet))throw(type="Logicore.Excel",message="Sheet '#arguments.sheetName#' was not found in #getFileFromPath(arguments.path)#.");
            var formatter=createObject("java","org.apache.poi.ss.usermodel.DataFormatter").init();
            var dateUtil=createObject("java","org.apache.poi.ss.usermodel.DateUtil");
            var header=sheet.getRow(arguments.headerRow-1);
            if(isNull(header))return[];
            var headers=[];
            var last=header.getLastCellNum();
            for(var c=0;c<last;c++){
                var cell=header.getCell(c);
                var name=isNull(cell)?"Column"&(c+1):trim(formatter.formatCellValue(cell));
                if(!len(name))name="Column"&(c+1);
                var base=name;var suffix=2;while(arrayFindNoCase(headers,name)){name=base&"_"&suffix;suffix++;}
                arrayAppend(headers,name);
            }
            var rows=[];
            for(var r=arguments.headerRow;r<=sheet.getLastRowNum();r++){
                var row=sheet.getRow(r);if(isNull(row))continue;
                var item={};var nonblank=false;
                for(var c=0;c<arrayLen(headers);c++){
                    var cell=row.getCell(c);
                    var value="";
                    if(!isNull(cell)){
                        var cellType=cell.getCellType().toString();
                        if(cellType=="NUMERIC" && dateUtil.isCellDateFormatted(cell)) value=cell.getDateCellValue();
                        else if(cellType=="NUMERIC") value=cell.getNumericCellValue();
                        else if(cellType=="BOOLEAN") value=cell.getBooleanCellValue();
                        else if(cellType=="FORMULA"){
                            var cached=cell.getCachedFormulaResultType().toString();
                            if(cached=="NUMERIC")value=dateUtil.isCellDateFormatted(cell)?cell.getDateCellValue():cell.getNumericCellValue();
                            else if(cached=="BOOLEAN")value=cell.getBooleanCellValue();
                            else if(cached=="STRING")value=cell.getStringCellValue();
                        }else value=formatter.formatCellValue(cell);
                    }
                    item[headers[c+1]]=value;
                    if(!(isSimpleValue(value)&&trim(value&"")==""))nonblank=true;
                }
                if(nonblank)arrayAppend(rows,item);
            }
            return rows;
        } finally { wb.close();fis.close(); }
    }

    array function readFirstSheet(required string path,numeric headerRow=1){
        var fis=createObject("java","java.io.FileInputStream").init(arguments.path);
        var wb="";
        try{wb=createObject("java","org.apache.poi.ss.usermodel.WorkbookFactory").create(fis);}catch(any e){fis.close();throw(type="Logicore.Excel",message="The uploaded file is not a readable Excel workbook (#getFileFromPath(arguments.path)#).",detail=e.message);}
        try{var name=wb.getSheetAt(0).getSheetName();}finally{wb.close();fis.close();}
        return readSheet(arguments.path,name,arguments.headerRow);
    }

    array function headers(required string path){
        var fis=createObject("java","java.io.FileInputStream").init(path);var wb=createObject("java","org.apache.poi.ss.usermodel.WorkbookFactory").create(fis);
        try{var row=wb.getSheetAt(0).getRow(0);var headers=[];if(isNull(row))return headers;var fmt=createObject("java","org.apache.poi.ss.usermodel.DataFormatter").init();for(var i=0;i<row.getLastCellNum();i++){var cell=row.getCell(i);arrayAppend(headers,isNull(cell)?"":fmt.formatCellValue(cell));}return headers;}finally{wb.close();fis.close();}
    }

    array function sheetNames(required string path){
        var fis=createObject("java","java.io.FileInputStream").init(arguments.path);
        var wb=createObject("java","org.apache.poi.ss.usermodel.WorkbookFactory").create(fis);var out=[];
        try{for(var i=0;i<wb.getNumberOfSheets();i++)arrayAppend(out,wb.getSheetName(i));return out;}finally{wb.close();fis.close();}
    }

    void function writeWorkbook(required string path, required array sheets){
        var wb=createObject("java","org.apache.poi.xssf.usermodel.XSSFWorkbook").init();
        try{
            var styles=makeStyles(wb);
            for(var spec in arguments.sheets){
                var sheet=wb.createSheet(left(spec.name,31));
                var rows=spec.rows ?: [];
                var headers=spec.headers ?: deriveHeaders(rows);
                var r0=sheet.createRow(0);
                for(var c=1;c<=arrayLen(headers);c++){var cell=r0.createCell(c-1);cell.setCellValue(headers[c]);cell.setCellStyle(styles.header);}
                var rn=1;
                for(var item in rows){
                    var rr=sheet.createRow(rn);rn++;
                    for(var c=1;c<=arrayLen(headers);c++){
                        var cell=rr.createCell(c-1);var v=structKeyExists(item,headers[c])?item[headers[c]]:"";
                        setCell(cell,v,styles);
                    }
                }
                sheet.createFreezePane(0,1);
                for(var c=0;c<arrayLen(headers);c++){
                    try{sheet.autoSizeColumn(c);if(sheet.getColumnWidth(c)>14000)sheet.setColumnWidth(c,14000);}catch(any ignored){}
                }
            }
            var fos=createObject("java","java.io.FileOutputStream").init(arguments.path);try{wb.write(fos);}finally{fos.close();}
        } finally {wb.close();}
    }

    void function writeInvoice(required string path,required string title,required array lineItems,required struct summary,array dataSheets=[]){
        var wb=createObject("java","org.apache.poi.xssf.usermodel.XSSFWorkbook").init();
        try{
            var styles=makeStyles(wb);var sheet=wb.createSheet("Breakdown");
            var row=sheet.createRow(0);var cell=row.createCell(0);cell.setCellValue(arguments.title);cell.setCellStyle(styles.title);
            var headers=["Description","Units of Measure","Unit Price","Quantity","Total Amount"];
            row=sheet.createRow(2);for(var c=1;c<=5;c++){cell=row.createCell(c-1);cell.setCellValue(headers[c]);cell.setCellStyle(styles.header);}
            var rn=3;
            for(var li in arguments.lineItems){row=sheet.createRow(rn);rn++;setCell(row.createCell(0),li.description?:"",styles);setCell(row.createCell(1),li.uom?:"Each",styles);var cp=row.createCell(2);setCell(cp,li.unit_price?:0,styles);cp.setCellStyle(styles.money);setCell(row.createCell(3),li.quantity?:0,styles);var ct=row.createCell(4);setCell(ct,li.total?:((li.unit_price?:0)*(li.quantity?:0)),styles);ct.setCellStyle(styles.money);}
            rn++;
            for(var pair in [{label:"Subtotal",value:summary.subtotal?:0},{label:"Tax",value:summary.tax?:0},{label:"Total",value:summary.total?:0}]){row=sheet.createRow(rn);rn++;row.createCell(3).setCellValue(pair.label);cell=row.createCell(4);cell.setCellValue(javaCast("double",pair.value));cell.setCellStyle(styles.moneyBold);}
            for(var c=0;c<5;c++)sheet.setColumnWidth(c,c==0?16000:4500);
            for(var spec in arguments.dataSheets){
                var ds=wb.createSheet(left(spec.name,31));var rows=spec.rows?:[];var hs=spec.headers?:deriveHeaders(rows);var hr=ds.createRow(0);for(var c=1;c<=arrayLen(hs);c++){cell=hr.createCell(c-1);cell.setCellValue(hs[c]);cell.setCellStyle(styles.header);}var dr=1;for(var item in rows){var rr=ds.createRow(dr);dr++;for(var c=1;c<=arrayLen(hs);c++)setCell(rr.createCell(c-1),structKeyExists(item,hs[c])?item[hs[c]]:"",styles);}ds.createFreezePane(0,1);}
            var fos=createObject("java","java.io.FileOutputStream").init(arguments.path);try{wb.write(fos);}finally{fos.close();}
        }finally{wb.close();}
    }

    void function replaceSheets(required string source,required string path,required array sheets){
        var fis=createObject("java","java.io.FileInputStream").init(arguments.source);
        var wb=createObject("java","org.apache.poi.ss.usermodel.WorkbookFactory").create(fis);
        try{
            var styles=makeStyles(wb);
            for(var spec in arguments.sheets){
                var index=wb.getSheetIndex(spec.name);if(index>=0)wb.removeSheetAt(index);
                var sheet=wb.createSheet(spec.name);if(index>=0)wb.setSheetOrder(spec.name,index);
                var headers=spec.headers?:deriveHeaders(spec.rows);var header=sheet.createRow(0);
                for(var c=1;c<=arrayLen(headers);c++){var cell=header.createCell(c-1);cell.setCellValue(headers[c]);cell.setCellStyle(styles.header);}
                var rn=1;for(var row in spec.rows){var rr=sheet.createRow(rn++);for(var c=1;c<=arrayLen(headers);c++)setCell(rr.createCell(c-1),row[headers[c]]?:"",styles);}
                sheet.createFreezePane(0,1);for(var c=0;c<arrayLen(headers);c++)sheet.setColumnWidth(c,6000);
            }
            wb.setForceFormulaRecalculation(true);
            var out=createObject("java","java.io.FileOutputStream").init(arguments.path);try{wb.write(out);}finally{out.close();}
        }finally{wb.close();fis.close();}
    }

    // Source-produced blank layouts preserve column order, print settings,
    // styling, merges and live formulas. All runtime data is written by POI.
    void function fillTemplate(required string source,required string path,required struct cells,required array sheets){
        var fis=createObject("java","java.io.FileInputStream").init(arguments.source);
        var wb=createObject("java","org.apache.poi.ss.usermodel.WorkbookFactory").create(fis);
        try{
            var styles=makeStyles(wb);
            for(var spec in arguments.sheets){
                var sheet=wb.getSheet(spec.name);if(isNull(sheet))sheet=wb.createSheet(spec.name);
                var headers=spec.headers?:deriveHeaders(spec.rows);var colStyles=[];
                var prototype=sheet.getRow(1);
                for(var c=0;c<arrayLen(headers);c++){var style=wb.getCellStyleAt(0);if(!isNull(prototype)){var pc=prototype.getCell(c);if(!isNull(pc))style=pc.getCellStyle();}arrayAppend(colStyles,style);}
                for(var rn=sheet.getLastRowNum();rn>=1;rn--){var old=sheet.getRow(rn);if(!isNull(old))sheet.removeRow(old);}
                var header=sheet.getRow(0);if(isNull(header))header=sheet.createRow(0);
                for(var c=1;c<=arrayLen(headers);c++){var cell=header.getCell(c-1);if(isNull(cell)){cell=header.createCell(c-1);cell.setCellStyle(styles.header);}cell.setCellValue(headers[c]);}
                var rn=1;
                for(var item in spec.rows){var row=sheet.createRow(rn++);for(var c=1;c<=arrayLen(headers);c++){var cell=row.createCell(c-1);cell.setCellStyle(colStyles[c]);var v=structKeyExists(item,headers[c])&&arrayFind(headers,headers[c])==c?item[headers[c]]:"";setCell(cell,v,styles);if(structKeyExists(spec.formats?:{},headers[c])){var st=wb.createCellStyle();st.cloneStyleFrom(cell.getCellStyle());st.setDataFormat(wb.createDataFormat().getFormat(spec.formats[headers[c]]));cell.setCellStyle(st);}}}
                if(!arrayLen(spec.rows)&&len(spec.emptyMessage?:""))sheet.createRow(1).createCell(0).setCellValue(spec.emptyMessage);
                for(var table in sheet.getTables()){
                    var endCol=table.getEndColIndex();
                    var area=createObject("java","org.apache.poi.ss.util.AreaReference").init(createObject("java","org.apache.poi.ss.util.CellReference").init(0,0),createObject("java","org.apache.poi.ss.util.CellReference").init(javaCast("int",max(1,arrayLen(spec.rows))),javaCast("int",endCol)),createObject("java","org.apache.poi.ss.SpreadsheetVersion").EXCEL2007);
                    table.setArea(area);table.updateReferences();
                }
            }
            for(var sheetName in arguments.cells){
                var sheet=wb.getSheet(sheetName);
                for(var address in arguments.cells[sheetName]){
                    var ref=createObject("java","org.apache.poi.ss.util.CellReference").init(address);var row=sheet.getRow(ref.getRow());if(isNull(row))row=sheet.createRow(ref.getRow());var cell=row.getCell(ref.getCol());if(isNull(cell))cell=row.createCell(ref.getCol());
                    var v=arguments.cells[sheetName][address];
                    if(isStruct(v)&&structKeyExists(v,"formula")){cell.setCellFormula(v.formula);if(structKeyExists(v,"value"))cell.setCellValue(javaCast("double",v.value));}
                    else setCell(cell,v,styles);
                }
            }
            wb.setForceFormulaRecalculation(true);
            var out=createObject("java","java.io.FileOutputStream").init(arguments.path);try{wb.write(out);}finally{out.close();}
        }finally{wb.close();fis.close();}
    }

    private struct function makeStyles(required any wb){
        var IndexedColors=createObject("java","org.apache.poi.ss.usermodel.IndexedColors");
        var hs=wb.createCellStyle();hs.setFillForegroundColor(IndexedColors.DARK_BLUE.getIndex());hs.setFillPattern(createObject("java","org.apache.poi.ss.usermodel.FillPatternType").SOLID_FOREGROUND);var hf=wb.createFont();hf.setBold(true);hf.setColor(IndexedColors.WHITE.getIndex());hs.setFont(hf);
        var title=wb.createCellStyle();var tf=wb.createFont();tf.setBold(true);tf.setFontHeightInPoints(javaCast("short",14));title.setFont(tf);
        var money=wb.createCellStyle();money.setDataFormat(wb.createDataFormat().getFormat("$##,####0.00"));
        var moneyBold=wb.createCellStyle();moneyBold.cloneStyleFrom(money);var bf=wb.createFont();bf.setBold(true);moneyBold.setFont(bf);
        var dateStyle=wb.createCellStyle();dateStyle.setDataFormat(wb.createDataFormat().getFormat("mm-dd-yyyy"));
        return {header:hs,title:title,money:money,moneyBold:moneyBold,date:dateStyle};
    }
    private void function setCell(required any cell,any value="",required struct styles){
        // Clear the original OOXML cell type (blank inline strings in openpyxl
        // templates otherwise retain inlineStr while POI writes a value node).
        cell.setBlank();
        // Preserve text identifiers (leading zeros, long tracking IDs and "Yes").
        // isDate/isNumeric coerce strings and would silently change their meaning.
        if(isInstanceOf(arguments.value,"java.lang.String")){cell.setCellValue(javaCast("string",arguments.value));}
        else if(isInstanceOf(arguments.value,"java.util.Date")){cell.setCellValue(arguments.value);cell.setCellStyle(arguments.styles.date);}
        else if(isInstanceOf(arguments.value,"java.lang.Boolean")){cell.setCellValue(javaCast("boolean",arguments.value));}
        else if(isNumeric(arguments.value)){cell.setCellValue(javaCast("double",arguments.value));}
        else cell.setCellValue(arguments.value&"");
    }
    private array function deriveHeaders(required array rows){if(!arrayLen(arguments.rows))return[];return structKeyArray(arguments.rows[1]);}
}
