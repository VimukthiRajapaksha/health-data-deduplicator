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
import ballerina/io;
import ballerinax/health.fhir.r4;
import ballerina/log;

// FTP Client configuration
final ftp:ClientConfiguration clientConfig = {
    protocol: ftp:SFTP,
    host: ftpHost,
    port: ftpPort,
    auth: {
        credentials: {
            username: ftpUsername,
            password: ftpPassword
        }
    }
};


// Initialize FTP client
final ftp:Client ftpClient;

function init() returns error? {
    do {
        ftpClient = check new (clientConfig);
    } on fail error err {
        log:printError("Failed to initialize FTP client", err);
        return error("Failed to initialize FTP client", err);
    }
}

listener ftp:Listener CCDAFileService = new (protocol = ftp:SFTP, host = ftpHost,
    port = ftpPort,
    auth = {
        credentials: {
            username: ftpUsername,
            password: ftpPassword
        }
    },
    fileNamePattern = "(.*).xml",
    path = incomingCcdaFileDir,
    pollingInterval = 3
);

r4:Bundle finalBundle = {'type: "transaction", 'entry: []};

# File Listener Service to process incoming MRF files
# The service listens for new files in the specified directory and processes them
# by converting them to CSV format and uploading them to the specified directory.
service ftp:Service on CCDAFileService {
    remote function onFileChange(ftp:WatchEvent & readonly event, ftp:Caller caller) returns error? {
        
        do {
            foreach ftp:FileInfo addedFile in event.addedFiles {
                string fileName = addedFile.name;
                log:printInfo(string`CCDA File added: ${fileName}`);
                stream<byte[] & readonly, io:Error?> fileStream = check ftpClient->get(path = addedFile.pathDecoded);
                string fileContent = "";
                log:printInfo("-------- Started processing file content --------");
                check fileStream.forEach(function(byte[] & readonly chunk) {

                    string|error content = string:fromBytes(chunk);
                    if content is string {
                        fileContent += content;
                    } else {
                        log:printError("Error converting chunk to string", content);
                        return;
                    }
                });

                log:printInfo("-------- Finished consuming file content --------");
                log:printInfo("File content: ", fileContent = fileContent);
                if fileContent.startsWith("<?xml version=\"1.0\" encoding=\"UTF-8\"?>") {
                    fileContent = fileContent.substring(38);
                }
                xml|error xmlContent = xml:fromString(fileContent);
                if xmlContent is error {
                    log:printError("Invalid CCDA file recieved", xmlContent);
                    _ = moveFileToErrorDirectory(fileName, fileContent);
                    return;
                }
                log:printDebug("File content: ", fileContent = xmlContent);
                r4:Bundle|error? processResponse = processCcdaFileContent(xmlContent);
                if processResponse is error {
                    log:printError("Error processing file content", processResponse);
                    _ = moveFileToErrorDirectory(fileName, fileContent);
                    return;
                } else {
                    r4:Bundle processedBundle = <r4:Bundle>processResponse;
                    r4:BundleEntry[]? entry = processedBundle.entry;
                    if entry is r4:BundleEntry[] {
                        (<r4:BundleEntry[]>finalBundle.entry).push(...entry);
                    }

                    ftp:Error? deletedFile = ftpClient->delete(path = addedFile.pathDecoded);
                    if deletedFile is ftp:Error {
                        log:printError("Error deleting file", deletedFile);
                    }
                    ftp:Error? processedFile = ftpClient->put(path = processedCcdaFileDir + fileName, content = fileContent);
                    if processedFile is ftp:Error {
                        log:printError("Error moving file to processed directory", processedFile);
                    } else {
                        log:printInfo("File moved to processed directory successfully");
                    }
                    log:printInfo("File processed successfully");
                }
            }
            log:printInfo("-------- FHIR Bundle constructed --------");
            log:printInfo("Final Bundle: ", bundleContent = finalBundle);

            DeduplicatedAgentResponse agentResponse = check deduplicateBundle(finalBundle);
            log:printInfo("-------- FHIR Bundle deduplicated --------");
            log:printInfo("Deduplicated Bundle: ", bundleContent = agentResponse.bundle);
            log:printInfo("Deduplicated Bundle Summary: ", bundleContent = agentResponse.summary);

        } on fail error err {
            return error("Error processing file", err);
        }
    }

}
