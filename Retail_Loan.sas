%let path = /folders/myfolders/mortgage/;
%let flname = Retail_Loan;
libname loan xlsx "&path/&flname..xlsx";

/*********************Reading the Excel****************************/
proc sql ; /*into: names one or more macro variables to create or update*/
select count(memname) into :sheetcnt from dictionary.tables where libname='WKBOOK';
quit;

proc sql;/*compress: compiles a list of characters to keep or remove; %sysfunc is the name of the function to execute*/
select memname into :sheet1-:%sysfunc(compress(sheet&sheetcnt)) from dictionary.tables where libname='WKBOOK';
quit;

%macro readexcel(sheetname);
proc import datafile="&path/&flname..xlsx" 
out=%sysfunc(compress(&sheetname))
dbms=xlsx replace;
sheet="&sheetname";
getnames=yes;/*Specify whether SAS variable names should be generated from the first record in the input file.*/
run;
%mend readexcel;

/*****************************Creating the Datasets**************************/
%macro createdatasets;
%do i = 1 %to %eval(&sheetcnt - 2);
	%readexcel(&&sheet&i)
%end;
%mend createdatasets;

%createdatasets;

/*********************************************************************/
/* How many customers have applied loan ? */
proc sql;
title 'Number of Customers who applied for loan';
select count(distinct(Customer_ID)) LABEL= 'No. of Applicants' from application;
title;
quit;

/*Month wise distribution of loan applications and average loan amount and total loan amounts? */
title 'Month wise distribution of loan applications';
proc sql;
Select distinct MONTH(App_Date) label= 'Month of Loan App', 
count(App_ID) label = 'No of Applications',
mean(Loan_Amount) label = 'Average of Loan Amount',
sum(Loan_Amount) label = 'Total Loan Amount'
from application group by MONTH(App_Date);
title;
quit;

/*how many customers have applied multiple loans ( more than one loan), list those customer ids and loans applied?*/
title 'Number of Customers who applied for multiple loans';
proc sql;
Select Customer_ID, count(App_ID) from application group by Customer_ID having count(App_ID) > 1;
title;
quit;

/*Calculate LTV ratio ( loan amount to asset value) for each customer */
title 'LTV ratio for each customer';
proc sql;
Select Customer_ID, Round(sum(Loan_Amount)/sum(asset_Value),0.001) label = 'Tot' 
from application group by Customer_ID;
title;
quit;

/*Rank the Cities on decending order based on number of loans applied*/
title 'Ranking of Cities based on loans';
proc sql;
Select City,count(App_ID) label = 'Total Applications' 
from application group by City order by City desc;
title;
quit;


/* Rank cities decending order based on amount of loans applied */
title 'Ranking of Cities based on loan amount';
proc sql;
Select City,sum(Loan_Amount) label = 'Total Amount' 
from application group by City order by 2 desc;
title;
quit;

/*What is the average age of the customer for each city in the loans applied?*/
title 'Average age of Customers for each City';
proc sql;
Select City, avg(floor((App_Date-DOB)/365.25)) as Avg_Age from 
(Select distinct(Customer_ID), City, App_Date,DOB from application) group by City;
quit;

/*What is the max , min and average length of employment each type of loan?*/
title 'Statistical values for Length of employment';
proc means data = application min max mean maxdec=2;
var Emplymnt_Length_yrs;
Class Loan_Type;
title;
run;

/**********************************************************************************/
/* View for joining Doc_Track and Doc_ref tables */
proc sql noprint;
Create View docref_view as
Select a.Customer_ID, b.* from Doc_Track a inner Join Doc_ref b on a.Doc_Code=b.Doc_Code;
quit;

/* How many customers have submitted at least one of each type of document? (  id ,   address, and   income proof) */
title 'Customers having atleast each type of document';
proc sql;
Select count(distinct(Customer_ID)) as No_Of_Customers from (Select * from docref_view  group by Customer_ID having count(distinct(Doc_Type)) =3);
title;
quit;

/* List customers who have submitted more than one proof for at lease one of the type of document. Example : 2 ids, one income and one address */
title 'Customers who submitted more than one proof for atleast one document';
proc sql;
Select distinct (c.Customer_ID) from docref_view c group by (Customer_ID || Doc_Type)having count(Customer_ID || Doc_Type) > 1  ;
title;
quit;

/* List customer who submitted id and address proof but did not submit income proof.
*/
proc sql;
title 'Customers who submitted id and address proof but not income proof';
Select distinct(Customer_ID) from docref_view where Customer_ID in (Select Customer_ID from docref_view where Customer_ID in 
(Select distinct(Customer_ID) from docref_view where Doc_type = 'Identity proof') 
having Doc_type = 'Address proof')
except 
Select distinct(Customer_ID) from docref_view having Doc_type = 'Income proof';
title;
quit;

/* List customers who submitted Pay Stub as income proof and Passport as ID proof.*/
proc sql;
title 'Customers who submitted Pay Stub as income proof and Passport as ID proof';
Select Customer_ID from docref_view where Customer_ID in 
(Select Customer_ID from docref_view where Doc_type = 'Income proof' and Document_description='Pay stub') 
and Doc_type = 'Identity proof' and Document_description='Passport';
title;
quit;


/* List customers who submitted  atleast one income proof and at least one id proof and whose first name starts with J and location  either in Trenton or Jersey. */
proc sql;
title 'Customers who submitted  atleast one income proof and at least one id proof and whose first name starts with J and location  either in Trenton or Jersey';
Select distinct(app.Customer_ID), app.Last_Name,app.First_Name,app.city from (Select distinct(Customer_ID) from docref_view where Customer_ID in 
(Select Customer_ID from docref_view where Doc_type = 'Income proof') 
and Doc_type = 'Identity proof') doc inner join application app on doc.Customer_ID = app.Customer_ID
where app.First_Name like 'J%' and (app.city = 'Trenton' or app.city = 'Jersey');
title;
quit;

/* What is the time lag between first proof to the last proof submitted for the customers who has at least one document for each type of document.
*/
proc sql;
title 'Time lag between first proof to last proof submitted for the customers who has at least one document for each type of document';
Select ab.Customer_ID, (max(ab.Doc_Submitted_Day)-min(ab.Doc_Submitted_Day)) label='Time lag' from (Select * from Doc_Track where Customer_ID in (Select Customer_ID from docref_view where Customer_ID in (Select Customer_ID from docref_view where Customer_ID in 
(Select distinct(Customer_ID) from docref_view where Doc_type = 'Income proof') 
having Doc_type = 'Identity proof') having Doc_type = 'Address proof')) ab group by ab.Customer_ID;
title;
quit;

/* What is the time lag ( number of days) between first proof to the last proof submitted for the customer who has at least one document for each type of document.
*/
proc sql;
title 'Time lag between first proof to the last proof submitted for the customers who has at least one document for each type of document';
Select ab.Customer_ID, (max(ab.Doc_Submitted_Day)-min(ab.Doc_Submitted_Day)) label='Time lag' from (Select * from Doc_Track where Customer_ID in (Select Customer_ID from docref_view where Customer_ID in (Select Customer_ID from docref_view where Customer_ID in 
(Select distinct(Customer_ID) from docref_view where Doc_type = 'Income proof') 
having Doc_type = 'Identity proof') having Doc_type = 'Address proof')) ab group by ab.Customer_ID;
title;
quit;


/* What is the time lag ( number of days ) between application time and the first document submitted by each of the customer? 
*/
proc sql;
title 'Time lag between application time and the first document submitted by each of the customer';
Select ab.Customer_ID, ab.First_Name,ab.Last_Name,ab.App_Date, ab.Loan_Type,ab.Doc_Code,ab.Doc_Submitted_Day,
(ab.Doc_Submitted_Day-ab.App_Date) as Time_lag from 
(Select distinct app.Customer_ID, app.First_Name,app.Last_Name,app.Loan_Type,app.App_Date, dr.Doc_Code,dr.Doc_Submitted_Day 
from application app inner join Doc_Track dr 
on app.Customer_ID = dr.Customer_ID) ab 
group by ab.Customer_ID, ab.First_Name,ab.Last_Name,ab.App_Date,ab.Loan_Type 
having Time_lag = min(Time_lag);
title;
quit;

/*What is the Average time lag ( number of days ) between application time and the any first document submitted for customers across City?
*/
proc sql;
title 'Average time lag between application time and the any first document submitted for customers across City';
Select City,avg(Time_lag) as Avg_Time_Lag from (Select ab.Customer_ID, ab.First_Name,ab.Last_Name,ab.App_Date, ab.Loan_Type,ab.City,ab.Doc_Code,ab.Doc_Submitted_Day,
(ab.Doc_Submitted_Day-ab.App_Date) as Time_lag from 
(Select distinct app.Customer_ID, app.First_Name,app.Last_Name,app.Loan_Type,app.City,app.App_Date, dr.Doc_Code,dr.Doc_Submitted_Day 
from application app inner join Doc_Track dr 
on app.Customer_ID = dr.Customer_ID) ab 
group by ab.Customer_ID, ab.First_Name,ab.Last_Name,ab.Loan_Type ,ab.City,ab.App_Date
having Time_lag = min(Time_lag)) group by City;
title;
quit;

/********************************************************************/

/*What is the start date and end date of the transactions for 
each customer in the data given?*/
proc sql;
title 'Start date and End date of the transactions for each customer';
Select Customer_ID,min(Transaction_Date) as Start_Date format=mmddyy10.,max(Transaction_Date) as End_Date as Tran_Diff format=mmddyy10.
from loan.bank_transactions group by Customer_ID;
title;
quit;

/* What is the end of the day balance for each customer for each day?*/
proc sql;
Create table temp as
Select *, 
Case Transaction_Type
When 'Withdrawl' then -(Amount)
When 'Deposit' then Amount 
End as Net_Amount
from loan.Bank_Transactions;
quit;

data temp(keep = Customer_ID Transaction_Date Balance_Amount );
set temp;
by Customer_ID Transaction_Date;
if first.Customer_ID then Balance_Amount = 0;
Balance_Amount + Net_Amount;
if last.Transaction_Date then output;
run;

title 'End of the day balance for each customer for each day';
proc print data = temp;
run;
title;


/*What is daily average balance for the entire period given for each customer ? */
title 'Daily Average Balance for each Customer';
proc sql;
Select Customer_ID, avg(Balance_Amount ) format =dollar11.2 as Daily_Avg_Bal from temp group by Customer_ID;
quit;
title;


/*What is the monthly average balance (MAB) & monthly weighted average for each customer ? For each bank it may be different for this question use logic as given in this link, if there is no data for 1st of the month for any customer then consider earliest date before 7th as 1st day balance.: */
/* Monthly Average Balance(MAB) */
data temp(drop=eom);
set temp;                                                                                  
eom=intnx('month',Transaction_Date,0,'end');                       
format eom date9.;                                     
numdays=day(eom); 
run; 

proc sql;
title 'Monthly Average Balance for each customer'; 
Select Customer_ID, Month(Transaction_Date) as Month_Tran, 
numdays,sum(Balance_Amount)/numdays format =dollar11.2 as Month_Avg_Bal,eom
from temp group by Customer_ID,Month_Tran,numdays ;
title;
quit;


/* Monthly weighted average balance */
proc sql noprint;
Create table temp as
Select *, Month(Transaction_Date) as Month_Tran,
Case Transaction_Type
When 'Withdrawl' then -(Amount)
When 'Deposit' then Amount 
End as Net_Amount
from loan.Bank_Transactions;
quit;

data temp(keep = Customer_ID Month_Tran Balance_Amount );
set temp;
by Customer_ID Month_Tran;
if first.Customer_ID then Balance_Amount = 0;
Balance_Amount + Net_Amount;
if last.Month_Tran then output;
run;

proc sql;
title 'Monthly weighted average balance for each Customer';
Select Customer_ID, (sum(Balance_Amount)/12) format = dollar11.2 as monthly_weigh_avg from temp group by Customer_ID;
title;
quit;


/*What are the average number of withdrawls per month? Per week? For each customer?*/
/*Average withdrawls per week*/
proc sql;
title 'Average withdrawls per week';
Select ab.Customer_ID, avg(ab.Count_Tran) as Avg_Withd_per_Week from (Select a.Customer_ID,a.Week_num,count(*) as Count_Tran from 
(Select Customer_ID, Week(Transaction_Date) as Week_num, Month(Transaction_Date) as Month_Tran 
from Bank_Transactions where Transaction_type = 'Withdrawl') a group by a.Customer_ID, a.Week_num) ab group by ab.Customer_ID;
title;
quit;

/*Average withdrawls per month*/
proc sql;
title 'Average withdrawls per month';
Select ab.Customer_ID, avg(ab.Count_Tran) as Avg_Withd_per_Month from (Select a.Customer_ID,a.Month_Tran,count(*) as Count_Tran from (Select Customer_ID, Week(Transaction_Date) as Week_num, Month(Transaction_Date) as Month_Tran 
from Bank_Transactions where Transaction_type = 'Withdrawl') a group by a.Customer_ID, a.Month_Tran) ab group by ab.Customer_ID;
title;
quit;

/*What is the average number of deposits per month? Per week ? For each customer?*/
/*Average deposits per week*/
proc sql;
title 'Average deposits per week';
Select ab.Customer_ID, avg(ab.Count_Tran) as Avg_Withd_per_Week from (Select a.Customer_ID,a.Week_num,count(*) as Count_Tran from 
(Select Customer_ID, Week(Transaction_Date) as Week_num, Month(Transaction_Date) as Month_Tran 
from loan.Bank_Transactions where Transaction_type = 'Deposit') a group by a.Customer_ID, a.Week_num) ab group by ab.Customer_ID;
title;
quit;

/*Average deposits per month*/
proc sql;
title 'Average deposits per month';
Select ab.Customer_ID, avg(ab.Count_Tran) as Avg_Withd_per_Month from (Select a.Customer_ID,a.Month_Tran,count(*) as Count_Tran from (Select Customer_ID, Week(Transaction_Date) as Week_num, Month(Transaction_Date) as Month_Tran 
from loan.Bank_Transactions where Transaction_type = 'Deposit') a group by a.Customer_ID, a.Month_Tran) ab group by ab.Customer_ID;
quit;
title;


/*What are the total deposited amounts , with drawl amount and net balance for each month for each customer?*/
proc sql;
title 'Total Withdrawl , Deposited amount with Net Balance';
Select *, (Deposit_Amt-Withdrawl_Amt) as Net_Balance from (Select coalesce(a.Customer_ID,b.Customer_ID) as Customer_ID,
coalesce(a.Month_Tran,b.Month_Tran) as Month_Tran, Withdrawl_Amt, Deposit_Amt from (Select Customer_ID,Month(Transaction_Date) as Month_Tran,
sum(Amount) as Withdrawl_Amt from loan.bank_transactions 
where Transaction_Type = 'Withdrawl' group by Customer_ID,Month_Tran) a
inner join
(Select Customer_ID,Month(Transaction_Date) as Month_Tran,sum(Amount) as Deposit_Amt 
from loan.bank_transactions where Transaction_Type = 'Deposit' 
group by Customer_ID,Month_Tran) b
on a.Customer_ID = b.Customer_ID and a.Month_Tran = b.Month_Tran);
title;
quit;


/*report1: create macro for report to get the mean and sum for the loan amount requested by all customers by type of loan*/
%macro loan_type_amount;
proc tabulate data = loan.application format = dollar10.;
title "mean and summary of total loan amount per type of loan";
label loan_type = "type of loan"
          loan_amount = "amount of loan applied";
keylabel mean = "average of loan amount"
sum = "summation of loan amount";

table loan_type*loan_amount*(mean sum);
class loan_type;
var loan_amount;
run;
title;
%mend;
%loan_type_amount;

/*report2: create macro to get the minimum and maximum amount of loan applied by customer by type and city*/
%macro loan_type_city;
proc tabulate data = loan.application format = dollar10.;
title "max and min for loan amount per type and for each city";
label loan_type = "type of loan"
          loan_amount = "amount for loan"
          city = "city where loan is applied";
keylabel min = "minimum amount of loan"
          max = "maximum amount of loan";
table loan_type, city*loan_amount*(min max) / box = "information about type of loan with maximum and minimum loan requested per city";
class loan_type city;
var loan_amount;
run;
title;
%mend;
%loan_type_city;


/*report 3: create macro to get basic information about customer like name age city loan amountand loan tyoe in the report along with his total withdrawls and deposits in the title of report by passing customer id;*/
%macro loan_report(cusid);
data loan.application;
set loan.application;
age = int((today() - dob)/365);
run;
proc sql;
create table temp_trans as 
select transaction_type, sum(amount) as sum_amount
from loan.bank_transactions
where customer_id = "&cusid"
group by transaction_type;
quit;

data _null_;
set temp_trans;
if _n_ = 1 then call symputx('deposit', sum_amount);
else call symputx('withdrawl', sum_amount);
run;

proc print data = loan.application noobs;
title "total deposit for given candidate is &deposit and total withdrawl is &withdrawl";
where customer_id = "&cusid";
var first_name  last_name  age city loan_amount loan_type;
run;
%mend;
%loan_report(CID0000125);

/*report 4: create macto to return the information about the documents submitted by customer for loan application;*/
proc sql;
create table loan.documents as
select customer_id, dr.doc_code, dr.doc_type, document_description
from loan.doc_track as dt inner join loan.doc_ref as dr
on dt.doc_code = dr.doc_code;
quit;

%macro customer_docs(cusid);
proc print data = loan.documents label noobs;
title "documents submitted by customer number &cusid";
var doc_type document_description;
where customer_id = "&cusid";
label doc_type = "type of documents submmited"
document_description = "documents description";
run;
%mend;
%customer_docs(CID0000125);



