/**
 * @author            : salih.cendik
 * @last modified on  : 31-10-2023
 * @last modified by  : salih.cendik
**/
public class OpportunitySummaryReportJob implements Schedulable {
    public Map<String, Decimal> conversionRateMap;
    public Map<String, String> salesOrgToOwnerId;
    public List<Opportunity> oppsToCreate;
    public final String REPORT_REC_TYPE_ID = Schema.sObjectType.Opportunity.getRecordTypeInfosByDeveloperName().get('Report').getRecordTypeId();
    public Boolean isManuelSchedule = false;
    public Date reportLastDay;

    public void execute(SchedulableContext SC) {
        reportLastDay = getReportDate();
        setConversionMap(reportLastDay);
        Map<String, Summary> notQuotedOpenOpps = calculateNotQuotedOpenOppTotals();
        Map<String, Summary> quotedOpenOpps = calculateQuotedOpenOppTotals();
        Map<String, Summary> allOpenOpps = calculateAllOpenOppTotals(notQuotedOpenOpps, quotedOpenOpps);
        System.debug('notQuotedOpenOpps: '+notQuotedOpenOpps);
        System.debug('quotedOpenOpps: '+quotedOpenOpps);
        System.debug('allOpenOpps: '+allOpenOpps);
        
        deleteOldReportOpportunity();
        this.oppsToCreate = new List<Opportunity>();  
        setOwnerMap();
        createReportOpportunity(notQuotedOpenOpps, 'Not Quoted');
        createReportOpportunity(quotedOpenOpps, 'Quoted');
        createReportOpportunity(allOpenOpps, 'Open Opportunities');
        Database.SaveResult[] srList = Database.insert(this.oppsToCreate, true);
        generateErrorLogs(srList);
    }

    public void createReportOpportunity(Map<String, Summary> oppMap, String reportType) {
        Date reportDate = this.reportLastDay;
        for (String mapKey : oppMap.keySet()) {
            List<String> keys = mapKey.split('_');
            String company = nullCheck(keys[0]);
            String salesOrg = nullCheck(keys[1]);
            String recDevName = nullCheck(keys[2]);
            String division = nullCheck(keys[3]);
            String reportName = String.valueof(reportDate.year()) + '-' + String.valueof(reportDate.month()) + '-' + reportType;
            this.oppsToCreate.add(new Opportunity(
                RecordTypeId = this.REPORT_REC_TYPE_ID,
                Name = reportName,
                Report_Type__c = reportType,
                Company__c = company,
                Sales_Org__c = salesOrg,
                Distribution_Channel__c = getDistChannelCode(company, recDevName),
                Division__c = division,
                CloseDate = reportDate,
                Record_Count__c = oppMap.get(mapKey).totalRow,
                Total_Expected_Quantity__c = oppMap.get(mapKey).totalOppQty,
                Expected_Quantity_Unit__c = getUnit(division),
                Amount = oppMap.get(mapKey).totalAmount,
                OwnerId = getOwnerId(salesOrg),
                StageName = 'Open',
                CurrencyIsoCode = 'TRY'
            ));
        }
    }
    
    public void deleteOldReportOpportunity() {
        Date reportFirstDay = reportLastDay.toStartOfMonth();
        delete [SELECT Id FROM Opportunity 
        WHERE RecordTypeId = :this.REPORT_REC_TYPE_ID AND 
        Report_Type__c IN ('Quoted', 'Not Quoted', 'Open Opportunities') AND
        CloseDate >= :reportFirstDay AND CloseDate <= :reportLastDay];
    }

    public Map<String, Summary> calculateNotQuotedOpenOppTotals() {
        Boolean isQuotedOpp = false;
        AggregateResult[] notQuotedOppList = fetchOpenOpportunities(isQuotedOpp);
        if (notQuotedOppList.isEmpty()){
            return new Map<String, Summary>();
        }    
        return processAggregateResults(notQuotedOppList);
    }

    public Map<String, Summary> calculateQuotedOpenOppTotals() {
        Boolean isQuotedOpp = true;
        AggregateResult[] quotedOppList = fetchOpenOpportunities(isQuotedOpp);
        if (quotedOppList.isEmpty()){
            return new Map<String, Summary>();
        }   
        return processAggregateResults(quotedOppList);
    }

    public Map<String, Summary> calculateAllOpenOppTotals(Map<String, Summary> notQuotedOppMap, Map<String, Summary> quotedOppMap) {
        Map<String, Summary> filteredNotQuotedOppMap = new Map<String, Summary>(notQuotedOppMap);
        Map<String, Summary> filteredQuotedOppMap = new Map<String, Summary>(quotedOppMap);
        Map<String, Summary> allOppMap = new Map<String, Summary>();

        for (String key : notQuotedOppMap.keySet()) {
            if (!quotedOppMap.containsKey(key)){
                continue;
            } 
            Summary notQuotedSummary = notQuotedOppMap.get(key);
            Summary quotedSummary = quotedOppMap.get(key);
            Summary allOppSummary = new Summary();
            allOppSummary.setTotalRow(notQuotedSummary.totalRow + quotedSummary.totalRow);
            allOppSummary.setTotalOppQty(notQuotedSummary.totalOppQty + quotedSummary.totalOppQty);
            allOppSummary.setTotalAmount(notQuotedSummary.totalAmount + quotedSummary.totalAmount);
            allOppMap.put(key, allOppSummary);
            filteredNotQuotedOppMap.remove(key);
            filteredQuotedOppMap.remove(key);
        }
        allOppMap.putAll(filteredNotQuotedOppMap);
        allOppMap.putAll(filteredQuotedOppMap);
        return allOppMap;
    }

    public Map<String, Summary> processAggregateResults(List<AggregateResult> aggregateResults){
        Map<String, Summary> processedResult = new Map<String, Summary>();
        for (AggregateResult ar  : aggregateResults) {
            Decimal totalAmount = (Decimal) ar.get('totalAmount');
            String currCode = (String) ar.get('CurrencyIsoCode');
            String mapKey = generateMapKey(ar);
            if (!processedResult.containsKey(mapKey)){
                processedResult.put(mapKey, new Summary());
            } 
            processedResult.get(mapKey).setTotalRow((Integer) ar.get('totalRow'));
            processedResult.get(mapKey).setTotalOppQty((Decimal) ar.get('totalOppQty'));
            processedResult.get(mapKey).setTotalAmount(convertCurrency(totalAmount, currCode, 'TRY'));
        }
        return processedResult;
    } 

    public String generateMapKey(AggregateResult ar){
            String mapKey = '';
            mapKey += (String) ar.get('Company__c') + '_';
            mapKey += (String) ar.get('Sales_Org__c') + '_';
            mapKey += learnIfProjectOrWholesale((String) ar.get('recDevName')) + '_';
            mapKey += (String) ar.get('Division__c');
            return mapKey;
    }
    
    public List<AggregateResult> fetchOpenOpportunities(Boolean isQuotedOpp){
        Set<String> statusOpen = new Set<String>{'Open', 'Açik'};
        Set<String> statusClosed = new Set<String>{'Closed Won', 'Closed Lost'};  
        
        String selectClause = 'SELECT Company__c, Sales_Org__c, RecordType.DeveloperName recDevName, Division__c, CurrencyIsoCode, COUNT(Id) totalRow, SUM(Opportunity_Quantity__c) totalOppQty, SUM(Quote_Amount__c) totalAmount FROM Opportunity'+ ' '; 

        String whereClause = '';
        if (this.isManuelSchedule){
            whereClause += 'WHERE RecordTypeId != :REPORT_REC_TYPE_ID AND' + ' '; 
            whereClause += '((CreatedDate <= :reportLastDay AND StatusFormula__c IN :statusOpen AND Quote_Won_Total_Amount__c = null) OR (StatusFormula__c IN :statusClosed AND ActualCloseDate__c >= :reportLastDay))'+ ' ';
            whereClause += isQuotedOpp ?  'AND Last_Quote_Date__c != null' + ' ' : 'AND Last_Quote_Date__c = null' + ' ';
        }else{
            whereClause += 'WHERE RecordTypeId != :REPORT_REC_TYPE_ID AND' + ' '; 
            whereClause += 'Quote_Won_Total_Amount__c = null AND' + ' '; 
            whereClause += '(StatusFormula__c IN :statusOpen)' + ' '; 
            whereClause += isQuotedOpp ?  'AND Last_Quote_Date__c != null' + ' ' : 'AND Last_Quote_Date__c = null' + ' ';
        }
        String lastClause = 'GROUP BY Company__c, Sales_Org__c, RecordType.DeveloperName, Division__c, CurrencyIsoCode ORDER BY Company__c';
        
        String queryStr = selectClause + whereClause + lastClause;
        return Database.query(queryStr);
    }

    public void setConversionMap(Date dateFilter){
        conversionRateMap = new Map<String, Decimal>();
        List<DatedConversionRate> datedConversionRates = [SELECT ConversionRate, IsoCode FROM DatedConversionRate WHERE StartDate <= :dateFilter AND Nextstartdate > :dateFilter];
        for (DatedConversionRate datedConversionRate : datedConversionRates) {
            this.conversionRateMap.put(datedConversionRate.IsoCode, datedConversionRate.ConversionRate);
        }
    }

    public Date getReportDate() {
        Scheduled_Job_Setting__mdt setting = Scheduled_Job_Setting__mdt.getInstance('Open_Opportunity_Calculation');
        this.isManuelSchedule = setting?.Manual_Schedule__c;
        Integer reportYear = Date.today().year();
        Integer reportMonth = Date.today().month();
        if (this.isManuelSchedule){
            reportYear = (Integer) setting.Schedule_Year__c;   
            reportMonth = (Integer) setting.Schedule_Month__c;     
        }
        Integer numberOfReportDays = Date.daysInMonth(reportYear, reportMonth); 
        Date reportLastDay = Date.newInstance(reportYear, reportMonth, numberOfReportDays);
        return reportLastDay;
    }

    public Decimal convertCurrency(Decimal amount, String fromCurrencyCode, String toCurrencyCode){
        if (fromCurrencyCode == toCurrencyCode || amount == null || amount == 0) {
            return amount;
        }
        Decimal corporateRate = conversionRateMap.get(fromCurrencyCode).setScale(6);
        Decimal targetRate = conversionRateMap.get(toCurrencyCode).setScale(6);
        Decimal convertedAmount = (amount * (targetRate / corporateRate)).setScale(2);
        return convertedAmount;
    }
    
    public String getUnit(String division){
        if (division == '40'){ return 'ST';}
        else if (division == '50'){ return 'KG';}
        else { return 'm2';}
    }

    public void setOwnerMap(){
        List<User> defaultUsers = [SELECT Id, Sales_Org__c FROM User WHERE Flow_Default_User__c = true AND IsActive = true];
        this.salesOrgToOwnerId = new Map<String, String>();
        for (User defaultUser : defaultUsers) {
            this.salesOrgToOwnerId.put(defaultUser.Sales_Org__c, defaultUser.Id);
        }
    }

    public String getOwnerId(String salesOrg){
        return salesOrgToOwnerId.containsKey(salesOrg) ? salesOrgToOwnerId.get(salesOrg) : UserInfo.getUserId();
    }

    public String getDistChannelCode(String company, String recordTypeDevName) {
        String result;
        if (company == '0092'){
            if (recordTypeDevName == 'Wholesale') {
                result = '72';
            }else if (recordTypeDevName == 'RUProject'){
                result = '73';
            }
            return result;
        }
        
        if (recordTypeDevName =='Project' || recordTypeDevName == 'DEOpportunity' || recordTypeDevName == 'FL_Project'){
            result = '20';
        }else if (recordTypeDevName == 'Wholesale'){
            result = '10';
        }
        return result;
    }

    public String learnIfProjectOrWholesale(String recordTypeDevName){
        String projectOrWholesale;
        if (recordTypeDevName =='Project' || recordTypeDevName == 'DEOpportunity' || recordTypeDevName == 'FL_Project' || recordTypeDevName == 'RUProject'){
            projectOrWholesale = 'Project';
        }else if (recordTypeDevName == 'Wholesale'){
            projectOrWholesale = 'Wholesale';
        }
        return projectOrWholesale;
    }

    public String nullCheck(String checkedField){
        return checkedField != 'null' ? checkedField : null;
    }

    public void generateErrorLogs(List<Database.SaveResult> results){
        List<String> errors = new List<String>();
        for (Integer i = 0; i < results.size(); i++) {
            if (!results.get(i).isSuccess()) {
                errors.add('Record which got error : ' + this.oppsToCreate.get(i));
                for(Database.Error err : results.get(i).getErrors()) {
                    errors.add(err.getStatusCode() + ': ' + err.getMessage() + ' Fields that affected this error: ' + err.getFields());
                }
                errors.add('-------------------------------');
            }
        }
        if(!errors.isEmpty()) {
            System.debug('Error count : ' + errors.size() / 3);
            System.debug(String.join(errors, '\n'));
        }
    }

    public class Summary {
        Integer totalRow;
        Decimal totalOppQty;
        Decimal totalAmount;

        Summary(){
            this.totalRow = 0;
            this.totalOppQty = 0;
            this.totalAmount = 0;
        }
        
        public void setTotalRow(Integer row){
            this.totalRow += row;
        }

        public void setTotalOppQty(Decimal qty){
            if (qty == null) {
                qty = 0;
            }
            this.totalOppQty += qty;
        }

        public void setTotalAmount(Decimal amount){
            if (amount == null) {
                amount = 0;
            }
            this.totalAmount += amount;
        }
    }

}