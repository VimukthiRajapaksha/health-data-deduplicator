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

isolated function getDuplicateEntries(ResourceSummary[] resourceSummaries) returns DuplicateEntry[]|error {
    string agentResponse = check deduplicateAgent->run(query = resourceSummaries.toJsonString(), sessionId = uuid:createType4AsString());
    agentResponse = re `${"```"}json`.replace(agentResponse, "");
    agentResponse = re `${"```"}`.replace(agentResponse, "");

    log:printInfo("FHIR Bundle duplicate identification successful: ", openAiAgentResponse = agentResponse);

    if agentResponse.trim().length() != 0 {
        json|error jsonAgentResponse = agentResponse.trim().fromJsonString();
        if jsonAgentResponse is json {
            DuplicateEntry[]? duplicateEntries = check jsonAgentResponse.cloneWithType();
            if duplicateEntries is DuplicateEntry[] {
                return duplicateEntries;
            }
        } else {
            log:printError("Error parsing agent response to json ", 'error = jsonAgentResponse);
        }
    } else {
        log:printDebug("Received an empty deduplication response");
    }
    return [];
}

function constructResourceSummary(r4:Bundle bundle) returns ResourceSummary[]|error {
    ResourceSummary[] resourceSummaries = [];
    r4:BundleEntry[] entries = bundle.entry ?: [];

    foreach r4:BundleEntry entry in entries {
        if entry?.'resource is r4:Resource {
            r4:Resource 'resource = <r4:Resource>entry?.'resource;
            string? resourceId = 'resource.id;
            string? resourceType = 'resource.resourceType;
            ResourceSummary summary = {
                resourceId: resourceId,
                resourceType: <string>resourceType,
                fields: {}
            };
            json jsonResult = 'resource.toJson();
            match resourceType {
                "Patient" => {
                    // For Patients, use identifier OR name + birthDate + gender
                    json|error identifier = jsonResult.identifier;
                    json|error name = jsonResult.name;
                    json|error birthDate = jsonResult.birthDate;
                    json|error gender = jsonResult.gender;
                    summary.fields = {
                        "identifier": identifier is json ? <json>identifier : (),
                        "name": name is json ? <json>name : (),
                        "birthDate": birthDate is json ? <json>birthDate : (),
                        "gender": gender is json ? <json>gender : ()
                    };
                }
                "Immunization" => {
                    // For Immunizations, use vaccineCode + identifier + occurrenceDateTime + patient
                    json|error vaccineCode = jsonResult.vaccineCode;
                    json|error identifier = jsonResult.identifier;
                    json|error occurrenceDateTime = jsonResult.occurrenceDateTime;
                    json|error patient = jsonResult.patient;
                    summary.fields = {
                        "vaccineCode": vaccineCode is json ? <json>vaccineCode : (),
                        "identifier": identifier is json ? <json>identifier : (),
                        "occurrenceDateTime": occurrenceDateTime is json ? <json>occurrenceDateTime : (),
                        "patient": patient is json ? <json>patient : ()
                    };
                }
                "DiagnosticReport" => {
                    // For DiagnosticReports, use code + subject + effectiveDateTime + identifier
                    json|error code = jsonResult.code;
                    json|error effectivePeriod = jsonResult.effectivePeriod;
                    json|error identifier = jsonResult.identifier;
                    summary.fields = {
                        "code": code is json ? <json>code : (),
                        "effectivePeriod": effectivePeriod is json ? <json>effectivePeriod : (),
                        "identifier": identifier is json ? <json>identifier : ()
                    };
                }
                "AllergyIntolerance" => {
                    // For AllergyIntolerances, use reaction + identifier + recordedDate
                    json|error reaction = jsonResult.reaction;
                    json|error identifier = jsonResult.identifier;
                    json|error recordedDate = jsonResult.recordedDate;
                    summary.fields = {
                        "reaction": reaction is json ? <json>reaction : (),
                        "identifier": identifier is json ? <json>identifier : (),
                        "recordedDate": recordedDate is json ? <json>recordedDate : ()
                    };
                }
                "MedicationRequest" => {
                    // MedicationRequest, use medicationCodeableConcept + dosageInstruction
                    json|error medicationCodeableConcept = jsonResult.medicationCodeableConcept;
                    json|error dosageInstruction = jsonResult.dosageInstruction;
                    summary.fields = {
                        "medicationCodeableConcept": medicationCodeableConcept is json ? <json>medicationCodeableConcept : (),
                        "dosageInstruction": dosageInstruction is json ? <json>dosageInstruction : ()
                    };
                }
                "Condition" => {
                    // For Conditions, use code + onsetDateTime + identifier + category
                    json|error code = jsonResult.code;
                    json|error onsetDateTime = jsonResult.onsetDateTime;
                    json|error identifier = jsonResult.identifier;
                    json|error category = jsonResult.category;
                    summary.fields = {
                        "code": code is json ? <json>code : (),
                        "onsetDateTime": onsetDateTime is json ? <json>onsetDateTime : (),
                        "identifier": identifier is json ? <json>identifier : (),
                        "category": category is json ? <json>category : ()
                    };
                }
            }
            resourceSummaries.push(summary);
        }
    }
    return resourceSummaries;
}

function getResourceSignature(ResourceSummary summary) returns string?|error {
    string resourceSignature = "";
    //add match case for each resource type
    match summary.resourceType {
        "Patient" => {
            // For Patients, use identifier OR name + birthDate + gender
            map<json> fields = summary.fields;

            if fields.hasKey("identifier") {
                json? identifier = fields["identifier"];
                if identifier is json[] {
                    // Assuming the first identifier is the most relevant
                    // Check if the identifier has a value
                    if identifier[0].value is string {
                        string identifierVal = check identifier[0].value;
                        return string `${summary.resourceType.toString()}|${identifierVal}`;
                    }
                }
            } else if fields.hasKey("name") {
                json? name = fields["name"];
                if name is json[] {
                    // Assuming the first name is the most relevant
                    // Check if the name has a family name
                    if name[0].family is string {
                        string familyName = check name[0].family;
                        json|error givenNameArr = name[0].given;
                        // Check if the name has a given name
                        if givenNameArr is json[] {
                            resourceSignature = string `${summary.resourceType.toString()}|${familyName}|${givenNameArr[0].toString()}`;
                        } else {
                            resourceSignature = string `${summary.resourceType.toString()}|${familyName}`;
                        }
                    }
                }
                if fields.hasKey("birthDate") {
                    json? birthDate = fields["birthDate"];
                    if birthDate is json {
                        resourceSignature = string `${resourceSignature}|${birthDate.toString()}`;
                    }
                }
                if fields.hasKey("gender") {
                    json? gender = fields["gender"];
                    if gender is json {
                        resourceSignature = string `${resourceSignature}|${gender.toString()}`;
                    }
                }
            }
        }
    }
    if resourceSignature == "" {
        return ();
    }
    return resourceSignature;
}

function removeDuplicatesFromBundle(DuplicatedEntry[] entries, r4:Bundle bundle) returns r4:Bundle {
    r4:BundleEntry[] dedupBundleEntries = [];
    r4:Bundle finalBundle = {'type: "transaction", 'entry: dedupBundleEntries};
    r4:BundleEntry[] bundleEntries = bundle.entry ?: [];
    // Iterate through the entries and remove duplicates, inside need to iterate through duplicated entries
    foreach r4:BundleEntry entry in bundleEntries {
        if entry?.'resource is r4:Resource {
            r4:Resource resourceResult = <r4:Resource>entry?.'resource;
            string? resourceId = resourceResult.id;
            if resourceId is string {
                foreach var duplicatedEntry in entries {
                    if duplicatedEntry.id != resourceId {
                        dedupBundleEntries.push(entry);
                    }
                }
            }
        }
    }
    return finalBundle;
}

