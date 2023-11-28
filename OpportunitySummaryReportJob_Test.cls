/**
 * @created by        : cenk.kalinoglu
 * @last modified on  : 28-11-2023
 * @last modified by  : salih.cendik
**/
@isTest
public class OpportunitySummaryReportJob_Test {
    @TestSetup
    static void createData() {
        Definition2__c state = new Definition2__c(
            RecordTypeId =  Schema.sObjectType.Definition2__c.getRecordTypeInfosByDeveloperName().get('State').getRecordTypeId(),
            Name = 'Test State',
            Country__c = 'TR'
        );
        insert state;
        
        Definition2__c district = new Definition2__c(
            RecordTypeId =  Schema.sObjectType.Definition2__c.getRecordTypeInfosByDeveloperName().get('District').getRecordTypeId(),
            Name = 'Test Disrict',
            State__c=state.Id
        );
        insert district;
        
        Account acc = new Account(
            RecordTypeId = Schema.sObjectType.Account.getRecordTypeInfosByDeveloperName().get('TR_Project').getRecordTypeId(),
            Name = 'Test Account',
            Country__c = 'TR',
            State__c = state.Id,
            District__c = district.Id,
            TaxNumber__c = '0123456789',
            SAPNumber__c = 'SapNumber',
            Status__c = 'Active',
            Company__c = '2100'
        );
        insert acc;

        Account_Sales_Org__c accountSalesOrg = new Account_Sales_Org__c(
            RecordTypeId = Schema.sObjectType.Account_Sales_Org__c.getRecordTypeInfosByDeveloperName().get('TR_Sales_Org').getRecordTypeId(),
            SalesOrg__c = '2101',
            DistributionChannel__c = '20',
            Division__c = '10',
            Account__c = acc.Id,
            CustomerPricingPresedure__c = '1',
            CompanyPicklist__c = '2100',
            Tax_Class__c = '0',
            Customer_Segment__c = 'A',
            Responsible__c = UserInfo.getUserId()
        );
        insert accountSalesOrg;

        Contact contact = new Contact(
            RecordTypeId = Schema.sObjectType.Contact.getRecordTypeInfosByDeveloperName().get('TR_Direct_Contact').getRecordTypeId(),
            AccountId = acc.Id,
            LastName = 'Test',
            FirstName = 'Test',
            Email = 'test@test.com.tr',  
            Mobile_Country__c = '+90',        
            MobilePhone = '0101010101'
        );
        insert contact;
        
        Id wholesaleRecTypeId = Schema.sObjectType.Opportunity.getRecordTypeInfosByDeveloperName().get('Wholesale').getRecordTypeId();
        Id ruProjectRecTypeId = Schema.sObjectType.Opportunity.getRecordTypeInfosByDeveloperName().get('RUProject').getRecordTypeId();
        Id projectRecordTypeId = Schema.sObjectType.Opportunity.getRecordTypeInfosByDeveloperName().get('Project').getRecordTypeId();
        
        Opportunity quotedOpp = new Opportunity(
            Name = 'Test Quoted Opp',
            StageName = 'Open',
            CloseDate = System.today().addDays(14),
            AccountId = acc.Id,
            Sales_Org__c = '2101',
            Division__c = '10',
            RecordTypeId = projectRecordTypeId,
            Company__c = '2100'
        );
        insert quotedOpp;

        Quote quote = new Quote(
            RecordTypeId =  Schema.sObjectType.Quote.getRecordTypeInfosByDeveloperName().get('TR_Quote').getRecordTypeId(),
            Name = 'Test Quote',
            Division__c = '10',
            OpportunityId = quotedOpp.Id,
            Sales_Org__c = '2101',
            Distribution_Channel__c = '20',
            CurrencyIsoCode = 'TRY',
            Company__c = '2100',
            Orderer__c = acc.Id,
            Orderer_Contact__c = contact.Id
        );
        insert quote;

        List<Opportunity> notQuotedOppsToInsert = new List<Opportunity>{
            new Opportunity(
                Name = 'Test Opportunity',
                StageName = 'Open',
                CloseDate = System.today().addDays(14),
                AccountId = acc.Id,
                Sales_Org__c = '9200',
                Division__c = '01RU',
                RecordTypeId = ruProjectRecTypeId,
                Company__c = '0092'
            ),
            new Opportunity(
                Name = 'Test Opportunity 1',
                StageName = 'Open',
                CloseDate = System.today().addDays(14),
                AccountId = acc.Id,
                Sales_Org__c = '2101',
                Division__c = '10',
                RecordTypeId = projectRecordTypeId,
                Company__c = '2100'
            ),
            new Opportunity(
                Name = 'Test Opportunity 2',
                StageName = 'Open',
                CloseDate = System.today(),
                AccountId = acc.Id,
                Sales_Org__c = '2101',
                Division__c = '10',
                RecordTypeId = wholesaleRecTypeId,
                Company__c = '2100'
            )
        };
        insert notQuotedOppsToInsert;
    }  
    
    @isTest
    static void testJob(){
        OpportunitySummaryReportJob oppSummJob = new OpportunitySummaryReportJob();
        Test.startTest();
        oppSummJob.execute(null);
        Assert.isFalse([SELECT Id FROM Opportunity WHERE Report_Type__c IN ('Not Quoted', 'Quoted', 'Open Opportunities')].isEmpty());
        Test.stopTest();
    }

    @isTest
    static void testJobForManuelSchedule(){
        OpportunitySummaryReportJob oppSummJob = new OpportunitySummaryReportJob();
        Test.startTest();
        oppSummJob.isManuelSchedule = true;
        Boolean isQuotedOpp = false;
        List<AggregateResult> result = oppSummJob.fetchOpenOpportunities(isQuotedOpp);
        Assert.isFalse(result.isEmpty());
        Test.stopTest();
    }
}