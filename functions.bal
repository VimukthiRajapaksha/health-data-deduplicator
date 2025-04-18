// Copyright (c) 2025, WSO2 LLC. (http://www.wso2.org) All Rights Reserved.
//
// WSO2 LLC. licenses this file to you under the Apache License,
// Version 2.0 (the "License"); you may not use this file except
// in compliance with the License.
// You may obtain a copy of the License at
//
// http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing,
// software distributed under the License is distributed on an
// "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
// KIND, either express or implied.  See the License for the
// specific language governing permissions and limitations
// under the License.

import ballerina/ftp;
import ballerina/log;
import ballerina/uuid;
import ballerinax/health.fhir.r4;
import ballerinax/health.fhir.r4utils.ccdatofhir;
import ballerinax/health.fhir.r4.international401;

function moveFileToErrorDirectory(string fileName, string fileContent) {
    ftp:Error? deletedFile = ftpClient->delete(path = incomingCcdaFileDir + fileName);
    if deletedFile is ftp:Error {
        log:printError("Error deleting file", deletedFile);
    }
    ftp:Error? failedFile = ftpClient->put(path = failedCcdaFileDir + fileName, content = fileContent);
    if failedFile is ftp:Error {
        log:printError("Error uploading file to error directory", failedFile);
    } else {
        log:printInfo("File moved to error directory successfully");
    }
}

function processCcdaFileContent(xml content) returns r4:Bundle|error? {

    r4:Bundle|r4:FHIRError ccdaToFhir = ccdatofhir:ccdaToFhir(content);
    if ccdaToFhir is r4:Bundle {
        log:printInfo("CCDA to FHIR conversion successful", convertedBundle = ccdaToFhir);
        return ccdaToFhir;
    } else {
        log:printError("Error converting CCDA to FHIR", ccdaToFhir);
        return error("Error converting CCDA to FHIR");
    }
}

isolated function deduplicateBundle(r4:Bundle bundle) returns DeduplicatedAgentResponse|error {
    string agentResponse = check deduplicateAgent->run(query = bundle.toJsonString(), sessionId = uuid:createType4AsString());
    agentResponse = re `${"```"}json`.replace(agentResponse, "");
    agentResponse = re `${"```"}`.replace(agentResponse, "");

    log:printDebug("FHIR Bundle deduplication successful: ", openAiAgentResponse = agentResponse);

    if agentResponse.trim().length() != 0 {
        json|error jsonAgentResponse = agentResponse.trim().fromJsonString();
        if jsonAgentResponse is json {
            DeduplicatedAgentResponse? deduplicatedAgentResponse = check jsonAgentResponse.cloneWithType();
            if deduplicatedAgentResponse is DeduplicatedAgentResponse {
                return deduplicatedAgentResponse;
            }
        } else {
            log:printError("Error parsing agent response to json ", 'error = jsonAgentResponse);
        }
    } else {
        log:printDebug("Received an empty deduplication response");
    }
    return {bundle: bundle, summary: []};
}

// Generates a unique signature for a resource based on key fields
function getResourceSignature(r4:Resource 'resource) returns string?|error {
    match 'resource {
        var r if r is international401:Patient => {
            // For Patients, use identifier OR name + birthDate + gender
            if r.identifier is r4:Identifier[] && (<r4:Identifier[]>r.identifier).length() > 0 {
                string? value = (<r4:Identifier[]>r.identifier)[0].value;
                if value is string {
                    return "Patient|" + value;
                } else {
                    return ();
                }
            } else {
                // string nameStr = r.name.length() > 0 ? 
                //     r.name[0].family + "|" + r.name[0].given.toString() : "";
                // return "Patient|" + nameStr + "|" + r.birthDate.toString() + "|" + r.gender.toString();
            }
        }
        // var r if r is international401:Practitioner => {
        //     // For Practitioners, use identifier OR name
        //     if r.identifier.length() > 0 {
        //         return "Practitioner|" + r.identifier[0].value;
        //     } else {
        //         string nameStr = r.name.length() > 0 ? 
        //             r.name[0].family + "|" + r.name[0].given.toString() : "";
        //         return "Practitioner|" + nameStr;
        //     }
        // }
        // var r if r is r4:Immunization => {
        //     // For Immunizations, use identifier OR vaccineCode + occurrence + patient reference
        //     if r.identifier.length() > 0 {
        //         return "Immunization|" + r.identifier[0].value;
        //     } else {
        //         string vaccineCode = r.vaccineCode.coding.length() > 0 ? 
        //             r.vaccineCode.coding[0].code.toString() : "";
        //         string occurrence = r.occurrenceDateTime is string ? 
        //             r.occurrenceDateTime.toString() : "";
        //         string patientRef = r.patient.reference is string ? 
        //             r.patient.reference.toString() : "";
        //         return "Immunization|" + vaccineCode + "|" + occurrence + "|" + patientRef;
        //     }
        // }
        // var r if r is r4:DiagnosticReport => {
        //     // For DiagnosticReports, use identifier OR code + effective date
        //     if r.identifier.length() > 0 {
        //         return "DiagnosticReport|" + r.identifier[0].value;
        //     } else {
        //         string code = r.code.coding.length() > 0 ? 
        //             r.code.coding[0].code.toString() : "";
        //         string effectiveDate = r.effectiveDateTime is string ? 
        //             r.effectiveDateTime.toString() : 
        //             (r.effectivePeriod.start is string ? r.effectivePeriod.start.toString() : "");
        //         return "DiagnosticReport|" + code + "|" + effectiveDate;
        //     }
        // }
        // var r if r is r4:AllergyIntolerance => {
        //     // For Allergies, use identifier OR code + patient reference
        //     if r.identifier.length() > 0 {
        //         return "AllergyIntolerance|" + r.identifier[0].value;
        //     } else {
        //         string code = r.code.coding.length() > 0 ? 
        //             r.code.coding[0].code.toString() : "";
        //         string patientRef = r.patient.reference is string ? 
        //             r.patient.reference.toString() : "";
        //         return "AllergyIntolerance|" + code + "|" + patientRef;
        //     }
        // }
        // var r if r is r4:Condition => {
        //     // For Conditions, use identifier OR code + onset date
        //     if r.identifier.length() > 0 {
        //         return "Condition|" + r.identifier[0].value;
        //     } else {
        //         string code = r.code.coding.length() > 0 ? 
        //             r.code.coding[0].code.toString() : "";
        //         string onsetDate = r.onsetDateTime is string ? 
        //             r.onsetDateTime.toString() : "";
        //         return "Condition|" + code + "|" + onsetDate;
        //     }
        // }
        // // Add other resource types as needed
        // var r => {
        //     // Default case - just use resource type and ID if available
        //     if r.id is string {
        //         return r.resourceType.toString() + "|" + r.id;
        //     }
        //     return error("No identifier or signature fields available for resource type: " + r.resourceType.toString());
        // }
    }
}