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

function deduplicateBundle(r4:Bundle bundle) returns DeduplicatedAgentResponse|error {

    string agentResponse = check deduplicateAgent->run(query = bundle.toJsonString(), sessionId = uuid:createType4AsString());
    agentResponse = re `${"```"}json`.replace(agentResponse, "");
    agentResponse = re `${"```"}`.replace(agentResponse, "");

    log:printInfo("FHIR Bundle deduplication successful: ", openAiAgentResponse = agentResponse);

    return agentResponse.ensureType();
}
