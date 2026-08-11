# Project Gallery: Cloud-Native Flask

This document contains visual verification of the multi-cloud infrastructure, CI/CD pipelines, observability dashboards, and disaster recovery procedures.

---

## 1. Live Application
<table width="100%">
  <tr>
    <td align="center"><img src="images/running-app.png" width="600px" alt="App UI"/></td>
    <td align="center"><img src="images/user-login.png" width="600px" alt="User Dashboard"/></td>
  </tr>
  <tr>
    <td align="center"><b>Application Home Page</b></td>
    <td align="center"><b>User Login & Wishlist</b></td>
  </tr>
</table>

---

## 2. GitOps Delivery (Argo CD)
<table width="100%">
  <tr>
    <td align="center"><img src="images/argo-ui-azure.png" width="600px" alt="Azure ArgoCD"/></td>
    <td align="center"><img src="images/argo-ui-aws.png" width="650px" alt="AWS ArgoCD"/></td>
  </tr>
  <tr>
    <td align="center"><b>Azure AKS Sync Status</b></td>
    <td align="center"><b>AWS EKS Sync Status</b></td>
  </tr>
</table>

---

## 3. Observability & Monitoring

### Azure Monitor & Log Analytics
*The dashboard below tracks cluster health, ingress traffic, and query performance.*
<div align="center">
  <img src="images/dashboard-1.png" width="800px" style="display:block; margin:0; padding:0;" />
  <img src="images/dashboard-2.png" width="800px" style="display:block; margin:0; padding:0;" />
  <img src="images/dashboard-3.png" width="800px" style="display:block; margin:0; padding:0;" />
  <img src="images/dashboard-4.png" width="800px" style="display:block; margin:0; padding:0;" />
</div>

### AWS CloudWatch
*Terraform-provisioned dashboard monitoring EKS node resources and RDS metrics.*
<div align="center">
  <img src="images/dashboard-aws-1.png" width="800px" style="display:block; margin:0; padding:0;" />
  <img src="images/dashboard-aws-2.png" width="800px" style="display:block; margin:0; padding:0;" />
  <img src="images/dashboard-aws-3.png" width="800px" style="display:block; margin:0; padding:0;" />
</div>

---
## 4. DNS & Network Verification
<table width="100%">
  <tr>
    <td align="center"><img src="images/dns.png" width="500px" /></td>
    <td align="center"><img src="images/dns-aws.png" width="680px" /></td>
  </tr>
  <tr>
    <td align="center"><b>Azure Ingress Resolution</b></td>
    <td align="center"><b>AWS NLB Endpoint Resolution</b></td>
  </tr>
</table> 

## 5. Cross-Cloud Disaster Recovery
*Visual walkthrough of the Azure MySQL to AWS S3 to AWS RDS restore process.*

**Step 1: Nightly Backup Job Execution**
<div align="center">
<img src="images/ACA-job-DR.png" width="800px" />
</div >

**Step 2: S3 Bucket Verification**
<div align="center">
<img src="images/backup-s3.png" width="800px" />
</div>
## 4. Disaster Recovery Validation (Cross-Cloud Data Consistency)

*This section demonstrates a successful Disaster Recovery event. After routing the Azure MySQL backup through S3 and restoring it into AWS RDS, the exact same user credentials and data state are immediately available on the independent AWS deployment.*

<table width="100%">
  <tr>
    <td align="center"><h3>Primary Environment (Azure)</h3></td>
    <td align="center"><h3>Recovery Environment (AWS)</h3></td>
  </tr>
  
  <!-- Row 1: Login Screens -->
  <tr>
    <td align="center"><img src="images/validate-dr-userlogin-azure1.png" width="450px" alt="Azure Login"/></td>
    <td align="center"><img src="images/validate-dr-userlogin-aws.png" width="450px" alt="AWS Login"/></td>
  </tr>
  <tr>
    <td align="center"><i>User 3 authenticating on Azure AKS</i></td>
    <td align="center"><i>User 3 authenticating on AWS EKS (Restored state)</i></td>
  </tr>

  <!-- Row 2: Data/Wishlist Screens -->
  <tr>
    <td align="center"><img src="images/validate-dr-userlogin-azure2.png" width="450px" alt="Azure User Data"/></td>
    <td align="center"><img src="images/validate-dr-userlogin-aws2.png" width="450px" alt="AWS User Data"/></td>
  </tr>
  <tr>
    <td align="center"><b>Azure Data State</b><br><i>User's original data prior to DR backup</i></td>
    <td align="center"><b>AWS Data State</b><br><i>Exact same data successfully restored & accessible</i></td>
  </tr>
</table>

---

